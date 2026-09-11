#!/usr/bin/env bash
# =====================================================================
# Hand By Hand (new) - API PHASE 1 acceptance suite
#
# Must print:  API PHASE 1 ACCEPTED
#
#   bash scripts/api.sh verify
#
# This is the direct descendant of hbh_pN_verify.sql, over HTTP instead
# of over SQL, and it obeys the same five rules:
#
#   1. The verdict ALWAYS prints. There is no `set -e` here: a probe
#      that dies must record a failure, not take the run with it. A
#      suite that exits before its verdict reads as a pass.
#   2. A negative test names the error CODE it expects. A refusal for
#      the wrong reason proves nothing and looks green.
#   3. The fixture is asserted by name, before the tests - not through
#      them, where a missing row surfaces later as a confusing refusal
#      from correct code.
#   4. Cleanup is a recorded check. Cleanup that swallows its own
#      failure is worse than no cleanup: it "succeeds" and kills the
#      next run for a reason that has nothing to do with the real one.
#   5. Counts against the append-only audit log are scoped to this
#      run's start. Otherwise the suite passes once and fails for ever.
#
# What the phase is actually for: a guardian who edits the identifier
# in a URL must be refused. Every other check here is scaffolding
# around the four in the `gate` group.
# =====================================================================

# The harness - probe helpers, field readers, psql access, the verdict -
# is shared with every other API suite. See tests/api/lib.sh.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
echo "=================== api phase 1 - the Go service ==================="
echo "base: $API_BASE"
echo

# =====================================================================
# FIXTURE - asserted by name, before any test runs
# =====================================================================

# Rebuild from a known state. The teardown runs first because a
# previous run that died half way leaves rows behind, and a fixture
# failing on those would report a broken fixture instead of the broken
# run that caused it.
FIXTURE_OUT="$(psqlf "$ROOT/tests/fixtures/a1_teardown.sql")"
FIXTURE_RC=$?
if [ "$FIXTURE_RC" != "0" ]; then
  chk fixture 'previous fixture removed' 1 "$FIXTURE_OUT"
else
  chk fixture 'previous fixture removed' 0
fi

FIXTURE_OUT="$(psqlf "$ROOT/tests/fixtures/a1_fixture.sql")"
FIXTURE_RC=$?
if [ "$FIXTURE_RC" != "0" ]; then
  chk fixture 'fixture applied' 1 "$FIXTURE_OUT"
else
  chk fixture 'fixture applied' 0
fi

RUN_START="$(psqlq "SELECT now()")"
chk fixture 'run start recorded' "$([ -n "$RUN_START" ] && echo 0 || echo 1)" 'could not read now() from the database'

CHILD_A="$(psqlq "SELECT child_id FROM hbh.children WHERE child_no = 'A1-A'")"
CHILD_B="$(psqlq "SELECT child_id FROM hbh.children WHERE child_no = 'A1-B'")"
chk fixture 'child A identifier known' "$([ -n "$CHILD_A" ] && echo 0 || echo 1)" 'A1-A missing'
chk fixture 'child B identifier known' "$([ -n "$CHILD_B" ] && echo 0 || echo 1)" 'A1-B missing'
neq fixture 'the two children are different rows' "$CHILD_A" "$CHILD_B"

eq fixture 'service answers /healthz' '200' "$(req GET /healthz)"
eq fixture 'service answers /readyz'  '200' "$(req GET /readyz)"

# The property the whole security model rests on, asserted by name from
# the database side. hbh_app must not be a superuser, must not have
# BYPASSRLS, and must own no table in hbh - Postgres bypasses row level
# security for all three, silently. The service also refuses to start
# without this; the suite states it independently so a change to the
# service cannot quietly remove the guarantee. (D-2)
eq fixture 'hbh_app is not a superuser'   'f' "$(psqlq "SELECT rolsuper FROM pg_roles WHERE rolname='hbh_app'")"
eq fixture 'hbh_app cannot bypass RLS'    'f' "$(psqlq "SELECT rolbypassrls FROM pg_roles WHERE rolname='hbh_app'")"
eq fixture 'hbh_app owns no table in hbh' '0' "$(psqlq "SELECT count(*) FROM pg_tables WHERE schemaname='hbh' AND tableowner='hbh_app'")"

# =====================================================================
# AUTHENTICATION
# =====================================================================
MOBILE_A='01500000001'
MOBILE_B='01500000002'
MOBILE_LOCKED='01500000003'
MOBILE_UNKNOWN='01599999999'
# On an application and on no user. Migration 0083 answers
# ENROLMENT_PENDING only for that pairing.
MOBILE_APPLIED='01599990001'
MOBILE_REJECTED='01599990002'

eq auth 'malformed mobile is refused' '400' \
  "$(req POST /api/v1/auth/otp/request '{"mobile":"not-a-number"}')"
eq auth 'malformed mobile names the code' 'VALIDATION' "$(jstr "$BODY" code)"

eq auth 'unknown field in body is refused' '400' \
  "$(req POST /api/v1/auth/otp/request '{"mobil":"01500000001"}')"

# AN UNREGISTERED NUMBER IS TOLD SO, by the owner's decision of
# 2026-09-05, carried out in the service on 2026-09-10 and in
# hbh.request_otp by migration 0083.
#
# These assertions used to demand the OPPOSITE - that the two answers be
# byte-identical - and they were right to, for the reason still written
# at otpRequestOut: forwarding this lets a stranger ask "is this person a
# client of a children's therapy centre?". What changed is not the risk
# but the weighing of it. The old behaviour sent a parent with no file to
# a code screen to wait for a message that was never coming, and said
# nothing; and the same fact was already answerable one call further on,
# where an unregistered number answered NO_PENDING_CODE and a registered
# one WRONG_CODE.
#
# So the suite now holds the NEW rule as firmly as it held the old one.
eq auth 'unknown number is answered, not silently accepted' '202' \
  "$(req POST /api/v1/auth/otp/request "{\"mobile\":\"$MOBILE_UNKNOWN\"}")"
eq auth 'and is told it is unknown' 'NOT_REGISTERED' "$(jstr "$BODY" status)"
eq auth 'unknown number carries no code' 'no' "$(jhas "$BODY" dev_code)"
# Nothing was sent, so a countdown would be counting down to nothing.
eq auth 'and carries no window to wait out' '0' "$(jnum "$BODY" expires_in_seconds)"
eq auth 'nor a resend timer' '0' "$(jnum "$BODY" resend_in_seconds)"

# A LOCKED ACCOUNT IS STILL WITHHELD, and this is the check that keeps
# the change from spreading. "This number exists but is locked" is a
# sharper fact about a named family than "this number exists", nobody
# asked for it, and a locked family is one the centre already has on the
# phone. It must be indistinguishable from a normal send.
eq auth 'locked account is accepted like any other' '202' \
  "$(req POST /api/v1/auth/otp/request "{\"mobile\":\"$MOBILE_LOCKED\"}")"
LOCKED_STATUS="$(jstr "$BODY" status)"
LOCKED_TTL="$(jnum "$BODY" expires_in_seconds)"
eq auth 'a locked account does NOT say it is locked' 'SENT' "$LOCKED_STATUS"
eq auth 'and it is not called unregistered either' 'SENT' "$LOCKED_STATUS"
eq auth 'locked account carries no code' 'no' "$(jhas "$BODY" dev_code)"

eq auth 'registered number is accepted' '202' \
  "$(req POST /api/v1/auth/otp/request "{\"mobile\":\"$MOBILE_A\"}")"
# The pair that makes the locked check mean something: a real send and a
# locked account must be identical in every field a caller can read.
eq auth 'registered number returns the same status as locked' "$LOCKED_STATUS" "$(jstr "$BODY" status)"
eq auth 'registered number returns the same window as locked' "$LOCKED_TTL" "$(jnum "$BODY" expires_in_seconds)"
CODE_A="$(jstr "$BODY" dev_code)"
# dev_code is the ONE observable difference, and it exists only because
# OTP_ECHO is on. config.Load refuses to start a non-development process
# with that flag, and there is a unit test for exactly that refusal.
chk auth 'development echo produced a code' "$([ -n "$CODE_A" ] && echo 0 || echo 1)" \
  'no dev_code in the response - is OTP_ECHO on?'

# A second request inside OTP_RESEND_SECONDS is refused by the database,
# and the refusal must look like every other outcome from outside.
eq auth 'resend inside the window looks identical' '202' \
  "$(req POST /api/v1/auth/otp/request "{\"mobile\":\"$MOBILE_A\"}")"
eq auth 'resend inside the window issues nothing' 'no' "$(jhas "$BODY" dev_code)"

# A FAMILY WHO HAS APPLIED AND IS WAITING gets its own answer. They are
# not strangers - their application is open on the centre's desk - and
# the old behaviour put them at the same code screen, with the same
# silence, as somebody who mistyped a number.
#
# These run AFTER CODE_A has been read. Placed above it they overwrote
# $BODY between the request that issued the code and the line that reads
# it, and twenty-three checks failed downstream with nothing in any of
# their messages pointing back here.
eq auth 'a live application is named as pending' '202' \
  "$(req POST /api/v1/auth/otp/request "{\"mobile\":\"$MOBILE_APPLIED\"}")"
eq auth 'and says which state it is in' 'ENROLMENT_PENDING' "$(jstr "$BODY" status)"
eq auth 'a pending applicant gets no code' 'no' "$(jhas "$BODY" dev_code)"
eq auth 'and no window to wait out' '0' "$(jnum "$BODY" expires_in_seconds)"

# AND A REJECTED ONE IS NOT NAMED. This keeps the rule from becoming
# "every application is announced": "the centre considered you and said
# no" is a decision about a family, it helps nobody standing at a login
# screen, and nobody asked for it. Without this pair the check above
# passes on a rule that reveals every application there is.
eq auth 'a rejected application is not announced' '202' \
  "$(req POST /api/v1/auth/otp/request "{\"mobile\":\"$MOBILE_REJECTED\"}")"
eq auth 'it answers like any stranger' 'NOT_REGISTERED' "$(jstr "$BODY" status)"
eq auth 'and the word never appears' 'no' \
  "$(grep -qi 'reject' "$BODY" && echo yes || echo no)"

eq auth 'a wrong code is refused' '401' \
  "$(req POST /api/v1/auth/otp/verify "{\"mobile\":\"$MOBILE_A\",\"code\":\"000000\"}")"
eq auth 'a wrong code names the reason' 'WRONG_CODE' "$(jstr "$BODY" code)"
# The counter survived. hbh.verify_otp returns a status instead of
# raising precisely so this increment is not rolled back - an exception
# would make every guess free. OTP_MAX_ATTEMPTS is 5, so one used
# attempt leaves 4.
eq auth 'the failed attempt was counted' '4' "$(jnum "$BODY" attempts_left)"

eq auth 'the right code is accepted' '200' \
  "$(req POST /api/v1/auth/otp/verify "{\"mobile\":\"$MOBILE_A\",\"code\":\"$CODE_A\"}")"
TOKEN_A="$(jstr "$BODY" token)"
chk auth 'a session token was issued' "$([ -n "$TOKEN_A" ] && echo 0 || echo 1)" 'no token in the response'
eq auth 'the token is a bearer token' 'Bearer' "$(jstr "$BODY" token_type)"

# Single use. The same code again must not open a second session.
eq auth 'a consumed code cannot be reused' '401' \
  "$(req POST /api/v1/auth/otp/verify "{\"mobile\":\"$MOBILE_A\",\"code\":\"$CODE_A\"}")"
eq auth 'a consumed code names the reason' 'NO_PENDING_CODE' "$(jstr "$BODY" code)"

# The second family, for the gate tests below.
req POST /api/v1/auth/otp/request "{\"mobile\":\"$MOBILE_B\"}" >/dev/null
CODE_B="$(jstr "$BODY" dev_code)"
req POST /api/v1/auth/otp/verify "{\"mobile\":\"$MOBILE_B\",\"code\":\"$CODE_B\"}" >/dev/null
TOKEN_B="$(jstr "$BODY" token)"
chk auth 'the second family has a session' "$([ -n "$TOKEN_B" ] && echo 0 || echo 1)" 'no token for family B'

# =====================================================================
# IDENTITY
# =====================================================================
eq identity 'no token is refused'      '401' "$(req GET /api/v1/me)"
eq identity 'no token names the code'  'UNAUTHENTICATED' "$(jstr "$BODY" code)"
eq identity 'a forged token is refused' '401' "$(req GET /api/v1/me '' 'not-a-real-token')"

eq identity 'the session resolves to its own account' '200' "$(req GET /api/v1/me '' "$TOKEN_A")"
eq identity 'the account is the one that logged in' 'a1_parent_a' "$(jstr "$BODY" username)"
eq identity 'the account is a guardian'             'GUARDIAN'    "$(jstr "$BODY" user_type)"
eq identity 'the centre is derived, not claimed'    'HBH'         "$(jstr "$BODY" code)"

# A guardian holds almost nothing. What they can reach is decided by
# the link row, not by a permission - so CHILD.VIEW_ALL must be absent.
chk identity 'guardian holds PORTAL.VIEW' \
  "$(grep -q 'PORTAL.VIEW' "$BODY" && echo 0 || echo 1)" 'PORTAL.VIEW missing from /me'
chk identity 'guardian does NOT hold CHILD.VIEW_ALL' \
  "$(grep -q 'CHILD.VIEW_ALL' "$BODY" && echo 1 || echo 0)" 'a guardian was granted CHILD.VIEW_ALL'

# =====================================================================
# THE GATE
#
# This group is the phase. Everything above exists to make these six
# checks possible.
# =====================================================================
eq gate 'family A lists children' '200' "$(req GET /api/v1/children '' "$TOKEN_A")"
eq gate 'family A sees exactly one child' '1' "$(grep -o '"child_id"' "$BODY" | wc -l | tr -d ' ')"
eq gate 'family A sees their own child' 'A1-A' "$(jstr "$BODY" child_no)"

eq gate 'family A reads their own child' '200' "$(req GET "/api/v1/children/$CHILD_A" '' "$TOKEN_A")"
eq gate 'the child is the expected one' 'A1-A' "$(jstr "$BODY" child_no)"

# The refusal. Family A asks for family B's child by identifier - the
# URL edit this whole phase exists to stop. Nothing in the handler
# compares anything: the policy on hbh.children calls
# hbh.can_access_child() and the row is never handed over.
eq gate 'family A is refused family B child' '404' "$(req GET "/api/v1/children/$CHILD_B" '' "$TOKEN_A")"
# 404 and not 403, deliberately: a 403 would confirm that the child
# exists, and identifiers are trivial to walk.
eq gate 'the refusal does not confirm existence' 'NOT_FOUND' "$(jstr "$BODY" code)"
eq gate 'the refusal leaks no name' 'no' "$(jhas "$BODY" full_name_ar)"

# And the same in the other direction, so the result is a rule and not
# an accident of ordering.
eq gate 'family B is refused family A child' '404' "$(req GET "/api/v1/children/$CHILD_A" '' "$TOKEN_B")"
eq gate 'family B sees their own child' '200' "$(req GET "/api/v1/children/$CHILD_B" '' "$TOKEN_B")"
eq gate 'family B child is the expected one' 'A1-B' "$(jstr "$BODY" child_no)"

eq gate 'an unauthenticated read is refused' '401' "$(req GET "/api/v1/children/$CHILD_A")"

# The live-view switch is carried from the link row, not defaulted. The
# fixture sets it true for A and false for B, so a handler that ignored
# the column would fail one of these two.
req GET "/api/v1/children/$CHILD_A" '' "$TOKEN_A" >/dev/null
eq gate 'family A may watch the live stream' 'true' "$(jbool "$BODY" can_view_live)"
req GET "/api/v1/children/$CHILD_B" '' "$TOKEN_B" >/dev/null
eq gate 'family B may not watch the live stream' 'false' "$(jbool "$BODY" can_view_live)"

# =====================================================================
# SESSION LIFETIME
# =====================================================================
eq session 'logout is accepted' '204' "$(req POST /api/v1/auth/logout '' "$TOKEN_A")"
# Revocation is immediate because the token is opaque and checked on
# every request. A stateless token would stay valid until it expired,
# which is the guarantee D-10 refuses to give up.
eq session 'a revoked token stops working at once' '401' "$(req GET /api/v1/me '' "$TOKEN_A")"
eq session 'the revoked token names the code' 'UNAUTHENTICATED' "$(jstr "$BODY" code)"
eq session 'the other session is untouched' '200' "$(req GET /api/v1/me '' "$TOKEN_B")"

# =====================================================================
# AUDIT
#
# Every count is scoped to RUN_START. The audit log is append-only, so
# an unscoped count passes on the first run and fails on every one
# after - which looks like a regression and is not one.
# =====================================================================
audit_count() { psqlq "SELECT count(*) FROM hbh.audit_log WHERE changed_at >= '$RUN_START'::timestamptz AND $1"; }

chk audit 'the successful login was recorded' \
  "$([ "$(audit_count "action = 'LOGIN' AND detail LIKE 'OTP_VERIFY OK%'")" -ge 1 ] && echo 0 || echo 1)" \
  'no LOGIN row for the accepted code'

chk audit 'the wrong code was recorded' \
  "$([ "$(audit_count "action = 'DENY' AND detail = 'OTP_VERIFY WRONG_CODE'")" -ge 1 ] && echo 0 || echo 1)" \
  'no DENY row for the refused code'

# The row that matters most. Nothing was returned to the client, the
# query looked entirely ordinary, and this is the only place the attempt
# is visible at all.
chk audit 'the refused child read was recorded' \
  "$([ "$(audit_count "action = 'DENY' AND detail = 'CHILD_NOT_VISIBLE child_id=$CHILD_B'")" -ge 1 ] && echo 0 || echo 1)" \
  "no DENY row for family A reaching child $CHILD_B"

# A trigger cannot see a SELECT, so a sensitive read is recorded here or
# it is not recorded anywhere.
chk audit 'the successful child read was recorded' \
  "$([ "$(audit_count "action = 'READ' AND detail = 'CHILD_PROFILE child_id=$CHILD_A'")" -ge 1 ] && echo 0 || echo 1)" \
  "no READ row for the child profile $CHILD_A"

chk audit 'the logout was recorded' \
  "$([ "$(audit_count "action = 'LOGIN' AND detail LIKE 'LOGOUT%'")" -ge 1 ] && echo 0 || echo 1)" \
  'no row for the logout'

# The trail identifies the attempt without publishing a phone number.
eq audit 'no full mobile number reaches the trail' '0' \
  "$(audit_count "changed_by LIKE '%$MOBILE_A%' OR detail LIKE '%$MOBILE_A%'")"
chk audit 'the masked actor is present instead' \
  "$([ "$(audit_count "changed_by LIKE 'mobile:____%'")" -ge 1 ] && echo 0 || echo 1)" \
  'no masked actor in the trail'

# =====================================================================
# TRANSPORT
# =====================================================================
eq transport 'an unknown path is a JSON 404' '404' "$(req GET /api/v1/nothing-here)"
eq transport 'the 404 names a code' 'NOT_FOUND' "$(jstr "$BODY" code)"
eq transport 'a wrong method is a JSON 405' '405' "$(req GET /api/v1/auth/logout)"
eq transport 'the 405 names a code' 'METHOD_NOT_ALLOWED' "$(jstr "$BODY" code)"

REQ_ID="$(curl -sS -o /dev/null -D - "$API_BASE/healthz" 2>/dev/null | tr -d '\r' | sed -n 's/^[Xx]-[Rr]equest-[Ii]d: //p')"
chk transport 'every response carries a request id' \
  "$([ -n "$REQ_ID" ] && echo 0 || echo 1)" 'no X-Request-Id header'

NOSNIFF="$(curl -sS -o /dev/null -D - "$API_BASE/healthz" 2>/dev/null | tr -d '\r' | sed -n 's/^[Xx]-[Cc]ontent-[Tt]ype-[Oo]ptions: //p')"
eq transport 'content type sniffing is refused' 'nosniff' "$NOSNIFF"

# An origin that is not on the allow list gets no CORS header at all.
ALLOW_ORIGIN="$(curl -sS -o /dev/null -D - -H 'Origin: https://evil.example' "$API_BASE/healthz" 2>/dev/null | tr -d '\r' | sed -n 's/^[Aa]ccess-[Cc]ontrol-[Aa]llow-[Oo]rigin: //p')"
eq transport 'an unlisted origin is not allowed' '' "$ALLOW_ORIGIN"

# =====================================================================
# RATE LIMIT
#
# Last, because it deliberately empties the bucket for this address and
# every HTTP check after it would be refused. scripts/api.sh restarts
# the service before the suite so the bucket always starts full.
#
# The limiter's arithmetic is unit tested. What a unit test cannot show
# is that it is actually WIRED to the login routes, and a limiter that
# is merely correct in isolation protects nothing. That is this check.
# =====================================================================
RATE_HIT=''
i=0
while [ "$i" -lt 200 ]; do
  if [ "$(req POST /api/v1/auth/otp/request '{"mobile":"01500000009"}')" = "429" ]; then
    RATE_HIT='yes'
    break
  fi
  i=$((i + 1))
done
chk rate 'the login endpoints are rate limited' "$([ -n "$RATE_HIT" ] && echo 0 || echo 1)" \
  'the burst was never refused - is the limiter wired to the auth routes?'
eq rate 'the refusal names a code' 'RATE_LIMITED' "$(jstr "$BODY" code)"

# =====================================================================
# CLEANUP - a recorded check like any other
# =====================================================================
CLEAN_OUT="$(psqlf "$ROOT/tests/fixtures/a1_teardown.sql")"
CLEAN_RC=$?
if [ "$CLEAN_RC" != "0" ]; then
  chk cleanup 'fixture removed' 1 "$CLEAN_OUT"
else
  LEFT="$(psqlq "SELECT (SELECT count(*) FROM hbh.users WHERE username LIKE 'a1\\_%') + (SELECT count(*) FROM hbh.children WHERE child_no LIKE 'A1-%')")"
  eq cleanup 'nothing was left behind' '0' "$LEFT"
fi


verdict "API PHASE 1"
