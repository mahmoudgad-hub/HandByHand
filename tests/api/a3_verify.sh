#!/usr/bin/env bash
# =====================================================================
# Hand By Hand (new) - API PHASE 3 acceptance suite
#
# Must print:  API PHASE 3 ACCEPTED
#
#   bash scripts/api.sh verify 3
#
# Three things arrive together in this batch, and one of them is the
# most dangerous endpoint in the system.
#
#   * the home programme, and the first two endpoints that WRITE
#   * billing, read only - the portal never takes money
#   * the live stream
#
# The live group is the reason this suite exists. CLAUDE.md is explicit:
# a stream token is opaque, at most fifteen minutes, hashed at rest and
# bound to a session, a camera and a user; and no camera link, address
# or credential may appear anywhere a client can reach. So the checks
# below are mostly about what is NOT in a response.
#
# The fixture gives child A two guardians who differ in exactly one
# flag, can_view_live_flg. If A can watch and C cannot, the flag is the
# gate - not the family link and not the child.
#
# The harness and the five rules it enforces are in tests/api/lib.sh.
# =====================================================================

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "=================== api phase 3 - home, billing, live ==================="
echo "base: $API_BASE"
echo

# =====================================================================
# FIXTURE - asserted by name, before any test runs
# =====================================================================
OUT="$(psqlf "$ROOT/tests/fixtures/a3_teardown.sql")"
RC=$?
if [ "$RC" != "0" ]; then chk fixture 'previous fixture removed' 1 "$OUT"; else chk fixture 'previous fixture removed' 0; fi

OUT="$(psqlf "$ROOT/tests/fixtures/a3_fixture.sql")"
RC=$?
if [ "$RC" != "0" ]; then chk fixture 'fixture applied' 1 "$OUT"; else chk fixture 'fixture applied' 0; fi

RUN_START="$(psqlq "SELECT now()")"
CHILD_A="$(psqlq "SELECT child_id FROM hbh.children WHERE child_no='A3-A'")"
CHILD_B="$(psqlq "SELECT child_id FROM hbh.children WHERE child_no='A3-B'")"
SESSION="$(psqlq "SELECT s.session_id FROM hbh.therapy_sessions s JOIN hbh.children c ON c.child_id=s.child_id WHERE c.child_no='A3-A'")"
CA="$(psqlq "SELECT ca.child_activity_id FROM hbh.child_activities ca JOIN hbh.children c ON c.child_id=ca.child_id WHERE c.child_no='A3-A'")"
INV="$(psqlq "SELECT i.invoice_id FROM hbh.invoices i JOIN hbh.children c ON c.child_id=i.child_id WHERE c.child_no='A3-A' AND i.status <> 'DRAFT'")"
INV_DRAFT="$(psqlq "SELECT i.invoice_id FROM hbh.invoices i JOIN hbh.children c ON c.child_id=i.child_id WHERE c.child_no='A3-A' AND i.status = 'DRAFT'")"
CAM_PATH="$(psqlq "SELECT gateway_path FROM hbh.cameras WHERE code='A3-CAM1'")"
# Never let the needle be empty. grep -q "" matches every line, so an
# absent camera path would turn every "no leak" check below into a
# guaranteed pass - the worst kind of green.
CAM_PATH="${CAM_PATH:-__no_camera_path_in_fixture__}"
APPT="$(psqlq "SELECT a.appointment_id FROM hbh.appointments a JOIN hbh.children c ON c.child_id=a.child_id WHERE c.child_no='A3-A'")"

ok_if fixture 'child A known'          "$([ -n "$CHILD_A" ] && echo 0 || echo 1)" 'A3-A missing'
ok_if fixture 'child B known'          "$([ -n "$CHILD_B" ] && echo 0 || echo 1)" 'A3-B missing'
ok_if fixture 'running session known'  "$([ -n "$SESSION" ] && echo 0 || echo 1)" 'no session'
ok_if fixture 'home activity known'    "$([ -n "$CA" ] && echo 0 || echo 1)" 'no child activity'
ok_if fixture 'issued invoice known'   "$([ -n "$INV" ] && echo 0 || echo 1)" 'no issued invoice'
ok_if fixture 'draft invoice known'    "$([ -n "$INV_DRAFT" ] && echo 0 || echo 1)" 'no draft invoice'
ok_if fixture 'the appointment is known' "$([ -n "$APPT" ] && echo 0 || echo 1)" 'no appointment'
neq   fixture 'camera path known' '__no_camera_path_in_fixture__' "$CAM_PATH"
neq   fixture 'the two invoices differ' "$INV" "$INV_DRAFT"

eq fixture 'service answers /healthz' '200' "$(req GET /healthz)"

TOKEN_A="$(login 01500000022)"
TOKEN_B="$(login 01500000023)"
TOKEN_C="$(login 01500000024)"
ok_if fixture 'guardian A signed in' "$([ -n "$TOKEN_A" ] && echo 0 || echo 1)" 'no token for A'
ok_if fixture 'guardian B signed in' "$([ -n "$TOKEN_B" ] && echo 0 || echo 1)" 'no token for B'
ok_if fixture 'guardian C signed in' "$([ -n "$TOKEN_C" ] && echo 0 || echo 1)" 'no token for C'

# =====================================================================
# HOME PROGRAMME
# =====================================================================
eq home 'the assigned activities are readable' '200' "$(req GET "/api/v1/children/$CHILD_A/activities" '' "$TOKEN_A")"
eq home 'one activity is assigned' '1' "$(jcount "$BODY" child_activity_id)"
ok_if home 'the activity carries its instructions' \
  "$(grep -q 'ابدأي بالكلمات القصيرة' "$BODY" && echo 0 || echo 1)" 'no instructions'
ok_if home 'the activity carries its adherence' \
  "$(grep -q 'done_last_7' "$BODY" && echo 0 || echo 1)" 'no adherence figures'

eq home 'the reported days are readable' '200' "$(req GET "/api/v1/children/$CHILD_A/activity-log" '' "$TOKEN_A")"
eq home 'two days were already reported' '2' "$(jcount "$BODY" log_id)"

# The first write in this service.
eq home 'a day can be reported' '201' \
  "$(req POST "/api/v1/children/$CHILD_A/activities/$CA/log" '{"done":true,"note_ar":"تمّ اليوم"}' "$TOKEN_A")"
ok_if home 'the new entry has an identifier' \
  "$(grep -q '"log_id"' "$BODY" && echo 0 || echo 1)" 'no log_id returned'

# The same day again. The database refuses rather than overwriting,
# because a second tap is far likelier than a change of mind - and
# replacing what the family said the first time loses a real answer.
eq home 'the same day is refused, not overwritten' '409' \
  "$(req POST "/api/v1/children/$CHILD_A/activities/$CA/log" '{"done":false}' "$TOKEN_A")"
eq home 'the refusal names the reason' 'ALREADY_LOGGED' "$(jstr "$BODY" code)"

eq home 'a malformed day is refused' '400' \
  "$(req POST "/api/v1/children/$CHILD_A/activities/$CA/log" '{"log_date":"03/09/2026"}' "$TOKEN_A")"

eq home 'the requests are readable' '200' "$(req GET "/api/v1/children/$CHILD_A/requests" '' "$TOKEN_A")"
eq home 'the submitted request is there' '1' "$(jcount "$BODY" request_id)"

eq home 'a request can be submitted' '201' \
  "$(req POST "/api/v1/children/$CHILD_A/requests" "{\"kind_code\":\"RESCHEDULE\",\"appointment_id\":$APPT,\"body_ar\":\"أرجو تأجيل موعد الأسبوع القادم.\"}" "$TOKEN_A")"

# ck_req_appt: only a CALLBACK may omit the appointment, because a
# request to move or cancel one has to say which. A well-formed body the
# schema refuses is the CALLER's mistake - 400, not 500. Answering 500
# would blame the server for a rule the client broke, and would bury a
# real fault in a pile of them.
eq home 'a reschedule with no appointment is refused' '400' \
  "$(req POST "/api/v1/children/$CHILD_A/requests" '{"kind_code":"RESCHEDULE","body_ar":"بدون موعد"}' "$TOKEN_A")"
eq home 'that refusal names the code' 'VALIDATION' "$(jstr "$BODY" code)"

# A callback needs no appointment, and must still be accepted.
eq home 'a callback needs no appointment' '201' \
  "$(req POST "/api/v1/children/$CHILD_A/requests" '{"kind_code":"CALLBACK","body_ar":"أرجو الاتصال بي."}' "$TOKEN_A")"

# The accepted kinds are lookup rows, not a constant in Go - so the
# refusal can tell the client which kinds this centre actually takes.
eq home 'an unknown request kind is refused' '400' \
  "$(req POST "/api/v1/children/$CHILD_A/requests" '{"kind_code":"REFUND","body_ar":"x"}' "$TOKEN_A")"
ok_if home 'the refusal lists the accepted kinds' \
  "$(grep -q 'RESCHEDULE' "$BODY" && echo 0 || echo 1)" 'the accepted kinds were not returned'

# =====================================================================
# BILLING
# =====================================================================
eq bill 'the invoices are readable' '200' "$(req GET "/api/v1/children/$CHILD_A/invoices" '' "$TOKEN_A")"
eq bill 'only the issued invoice is listed' '1' "$(jcount "$BODY" invoice_id)"

# Money is an exact decimal carried as a string. 4000.00 as a JSON
# number would be a float on the way in and on the way out, and this is
# the one figure in the system that gets added up and compared.
ok_if bill 'amounts are exact decimals, not floats' \
  "$(grep -q '"total_amt":"4000.00"' "$BODY" && echo 0 || echo 1)" 'the total is not an exact string'

eq bill 'the issued invoice opens' '200' "$(req GET "/api/v1/invoices/$INV" '' "$TOKEN_A")"
eq bill 'its line is included' '1' "$(jcount "$BODY" line_id)"
eq bill 'its payment is included' '1' "$(jcount "$BODY" payment_id)"
ok_if bill 'the payment reference is withheld' \
  "$(grep -q '"reference"' "$BODY" && echo 1 || echo 0)" 'a payment reference reached the family'

# The DRAFT ladder, the billing twin of the report ladder in phase 2. A
# bill still being assembled is not a bill, and asking a family to pay a
# number that is still moving is the failure being prevented.
eq bill 'a draft invoice is refused' '404' "$(req GET "/api/v1/invoices/$INV_DRAFT" '' "$TOKEN_A")"
eq bill 'the refusal does not confirm existence' 'NOT_FOUND' "$(jstr "$BODY" code)"

eq bill 'the packages are readable' '200' "$(req GET "/api/v1/children/$CHILD_A/packages" '' "$TOKEN_A")"
eq bill 'one package is held' '1' "$(jcount "$BODY" child_package_id)"
ok_if bill 'the remaining sessions are computed' \
  "$(grep -q '"sessions_left":8' "$BODY" && echo 0 || echo 1)" 'sessions_left is wrong'

eq bill 'the balance is readable' '200' "$(req GET "/api/v1/children/$CHILD_A/balance" '' "$TOKEN_A")"
ok_if bill 'the outstanding amount is exact' \
  "$(grep -q '"outstanding_amt":"2500.00"' "$BODY" && echo 0 || echo 1)" 'the outstanding amount is wrong'
ok_if bill 'the currency comes from the centre' \
  "$(grep -q '"currency_code":"EGP"' "$BODY" && echo 0 || echo 1)" 'no currency on the balance'

# =====================================================================
# LIVE - FAIL CLOSED
#
# This runs BEFORE anything is configured, because it is the state a
# fresh install is in and the state it must stay in until somebody
# deliberately points the centre at a named tunnel on a domain it owns.
# =====================================================================
eq live 'an unconfigured gateway refuses to stream' '503' \
  "$(req POST "/api/v1/sessions/$SESSION/stream" '{}' "$TOKEN_A")"
eq live 'the refusal names the reason' 'STREAM_UNAVAILABLE' "$(jstr "$BODY" code)"
ok_if live 'no token was minted while refusing' \
  "$([ "$(psqlq "SELECT count(*) FROM hbh.stream_tokens t JOIN hbh.therapy_sessions s ON s.session_id=t.session_id JOIN hbh.children c ON c.child_id=s.child_id WHERE c.child_no='A3-A'")" = "0" ] && echo 0 || echo 1)" \
  'a stream token exists even though the gateway refused'

# Now configure a gateway. 127.0.0.1:9 is the discard port: it refuses
# every connection, which is what proves the proxy resolved server-side
# and tried to reach it without ever telling the client where it went.
psqlq "UPDATE hbh.sys_params SET param_value='http://127.0.0.1:9/media' WHERE center_id IS NULL AND param_code='MEDIA_GATEWAY_BASE_URL'" >/dev/null
psqlq "UPDATE hbh.sys_params SET param_value='false' WHERE center_id IS NULL AND param_code='MEDIA_GATEWAY_IS_TEMPORARY'" >/dev/null

# =====================================================================
# LIVE - THE GATE
# =====================================================================
jar_clear
eq live 'the permitted guardian may open a stream' '201' \
  "$(req POST "/api/v1/sessions/$SESSION/stream" '{}' "$TOKEN_A")"

# What must NOT be in that response. Each of these is a rule from
# CLAUDE.md, checked against the bytes the client actually received.
ok_if live 'the response carries no token' \
  "$(grep -q '"token"' "$BODY" && echo 1 || echo 0)" 'A STREAM TOKEN WAS RETURNED TO THE CLIENT'
ok_if live 'the response carries no camera path' \
  "$(grep -q "$CAM_PATH" "$BODY" && echo 1 || echo 0)" 'THE CAMERA GATEWAY PATH REACHED THE CLIENT'
ok_if live 'the response carries no camera identifier' \
  "$(grep -q 'camera' "$BODY" && echo 1 || echo 0)" 'a camera identifier reached the client'
ok_if live 'the response carries no gateway address' \
  "$(grep -q '127.0.0.1' "$BODY" && echo 1 || echo 0)" 'THE GATEWAY ADDRESS REACHED THE CLIENT'

COOKIE="$(setcookie)"
ok_if live 'the token travels as a cookie' \
  "$(echo "$COOKIE" | grep -q 'hbh_stream=' && echo 0 || echo 1)" 'no stream cookie was set'
ok_if live 'the cookie is HttpOnly' \
  "$(echo "$COOKIE" | grep -qi 'HttpOnly' && echo 0 || echo 1)" 'the cookie is readable by script'
ok_if live 'the cookie is SameSite=Strict' \
  "$(echo "$COOKIE" | grep -qi 'SameSite=Strict' && echo 0 || echo 1)" 'another site could embed the stream'
ok_if live 'the cookie is scoped to the playback path' \
  "$(echo "$COOKIE" | grep -q 'Path=/api/v1/stream' && echo 0 || echo 1)" 'the cookie is sent too widely'

# Fifteen minutes, enforced by the issuing function AND by a CHECK on
# the row. Nothing a caller sends can widen it.
TTL="$(jnum "$BODY" expires_in_seconds)"
ok_if live 'the window is at most fifteen minutes' \
  "$([ -n "$TTL" ] && [ "$TTL" -le 900 ] && [ "$TTL" -gt 0 ] && echo 0 || echo 1)" "expires_in_seconds=$TTL"

# The whole point of the fixture. C is a guardian of the SAME child, on
# the SAME running session. The only difference is can_view_live_flg.
jar_clear
eq live 'the same child, the other guardian, is refused' '403' \
  "$(req POST "/api/v1/sessions/$SESSION/stream" '{}' "$TOKEN_C")"
eq live 'the refusal names the code' 'FORBIDDEN' "$(jstr "$BODY" code)"
ok_if live 'the refusal leaks no camera path' \
  "$(grep -q "$CAM_PATH" "$BODY" && echo 1 || echo 0)" 'the camera path leaked in a refusal'

# Another family entirely: 404, not 403 - a 403 would confirm the
# session exists.
jar_clear
eq live 'another family is not told the session exists' '404' \
  "$(req POST "/api/v1/sessions/$SESSION/stream" '{}' "$TOKEN_B")"
eq live 'that refusal is NOT_FOUND' 'NOT_FOUND' "$(jstr "$BODY" code)"

jar_clear
eq live 'an unauthenticated caller cannot open a stream' '401' \
  "$(req POST "/api/v1/sessions/$SESSION/stream" '{}')"

# =====================================================================
# LIVE - PLAYBACK
# =====================================================================
jar_clear
eq media 'the playback path refuses without a cookie' '401' "$(req GET /api/v1/stream/media)"

req POST "/api/v1/sessions/$SESSION/stream" '{}' "$TOKEN_A" >/dev/null
# The gateway is the discard port, so this must fail to connect. 502
# proves the API resolved the token, found the path, and went looking -
# all server-side.
eq media 'an unreachable gateway is a bad gateway' '502' "$(req GET /api/v1/stream/media)"
eq media 'the failure names a code' 'STREAM_UNAVAILABLE' "$(jstr "$BODY" code)"
ok_if media 'the failure leaks no camera path' \
  "$(grep -q "$CAM_PATH" "$BODY" && echo 1 || echo 0)" 'THE CAMERA PATH LEAKED IN AN ERROR BODY'
ok_if media 'the failure leaks no gateway address' \
  "$(grep -q '127.0.0.1' "$BODY" && echo 1 || echo 0)" 'THE GATEWAY ADDRESS LEAKED IN AN ERROR BODY'

eq media 'the window can be closed early' '204' "$(req POST /api/v1/stream/close '' "$TOKEN_A")"
eq media 'a revoked window stops playing at once' '401' "$(req GET /api/v1/stream/media)"

# =====================================================================
# THE GATE, EXTENDED
# =====================================================================
for path in activities activity-log requests invoices packages balance; do
  eq gate "family B is refused child A $path" '404' \
    "$(req GET "/api/v1/children/$CHILD_A/$path" '' "$TOKEN_B")"
done

eq gate 'family B cannot log against child A' '404' \
  "$(req POST "/api/v1/children/$CHILD_A/activities/$CA/log" '{"done":true}' "$TOKEN_B")"
eq gate 'family B cannot submit for child A' '404' \
  "$(req POST "/api/v1/children/$CHILD_A/requests" '{"kind_code":"CALLBACK","body_ar":"x"}' "$TOKEN_B")"
eq gate 'family B is refused child A invoice' '404' "$(req GET "/api/v1/invoices/$INV" '' "$TOKEN_B")"

# =====================================================================
# AUDIT
# =====================================================================
audit_count() { psqlq "SELECT count(*) FROM hbh.audit_log WHERE changed_at >= '$RUN_START'::timestamptz AND $1"; }

ok_if audit 'reading the home programme is recorded' \
  "$([ "$(audit_count "action='READ' AND detail='CHILD_ACTIVITIES child_id=$CHILD_A'")" -ge 1 ] && echo 0 || echo 1)" \
  'no READ row for the activities'

ok_if audit 'opening a live view is recorded' \
  "$([ "$(audit_count "action='READ' AND detail LIKE 'live view opened on session $SESSION%'")" -ge 1 ] && echo 0 || echo 1)" \
  'no record that somebody watched a child in therapy'

ok_if audit 'a refused live view is recorded' \
  "$([ "$(audit_count "action='DENY' AND detail LIKE 'live view refused for session $SESSION%'")" -ge 1 ] && echo 0 || echo 1)" \
  'no record of the refused live view'

ok_if audit 'every viewing leaves a stream_views row' \
  "$([ "$(psqlq "SELECT count(*) FROM hbh.stream_views v JOIN hbh.children c ON c.child_id=v.child_id WHERE c.child_no='A3-A'")" -ge 1 ] && echo 0 || echo 1)" \
  'somebody watched a child and left no trace'

# The trail is read by more people than the row it describes.
eq audit 'the camera path is nowhere in the audit trail' '0' \
  "$(audit_count "detail LIKE '%$CAM_PATH%' OR changed_by LIKE '%$CAM_PATH%'")"

# =====================================================================
# TRANSPORT
# =====================================================================
eq transport 'a wrong method on a write route is a JSON 405' '405' \
  "$(req DELETE "/api/v1/children/$CHILD_A/requests" '' "$TOKEN_A")"
eq transport 'the 405 names a code' 'METHOD_NOT_ALLOWED' "$(jstr "$BODY" code)"
eq transport 'a non-numeric invoice is not found' '404' "$(req GET /api/v1/invoices/abc '' "$TOKEN_A")"

# =====================================================================
# CLEANUP - a recorded check like any other
# =====================================================================
OUT="$(psqlf "$ROOT/tests/fixtures/a3_teardown.sql")"
RC=$?
if [ "$RC" != "0" ]; then
  chk cleanup 'fixture removed' 1 "$OUT"
else
  LEFT="$(psqlq "SELECT (SELECT count(*) FROM hbh.children WHERE child_no LIKE 'A3-%') + (SELECT count(*) FROM hbh.users WHERE username LIKE 'a3\\_%') + (SELECT count(*) FROM hbh.cameras WHERE code LIKE 'A3-%')")"
  eq cleanup 'nothing was left behind' '0' "$LEFT"
fi

# Five guards, not four: stream_views carries two. The teardown had to
# switch every one of them off, and a run that left one off would have
# silently removed an integrity guarantee for every later run.
eq cleanup 'the five append-only guards are back on' '5' \
  "$(psqlq "SELECT count(*) FROM pg_trigger WHERE tgname IN ('trg_ash_append_only','trg_ssh_append_only','trg_led_append_only','trg_view_append_only','trg_view_no_delete') AND tgenabled='O'")"

# The most important cleanup check in this suite. The gateway must be
# refusing again, or the next fresh run starts from a state no fresh
# install is ever in - and the fail-closed test above would pass
# vacuously for ever after.
eq cleanup 'the media gateway refuses again' 'true' \
  "$(psqlq "SELECT param_value FROM hbh.sys_params WHERE center_id IS NULL AND param_code='MEDIA_GATEWAY_IS_TEMPORARY'")"
eq cleanup 'the gateway address is cleared' '' \
  "$(psqlq "SELECT param_value FROM hbh.sys_params WHERE center_id IS NULL AND param_code='MEDIA_GATEWAY_BASE_URL'")"

verdict "API PHASE 3"
