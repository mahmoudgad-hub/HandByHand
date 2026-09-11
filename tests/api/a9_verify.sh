#!/usr/bin/env bash
# =====================================================================
# Hand By Hand (new) - API PHASE 9 acceptance suite
#
# Must print:  API PHASE 9 ACCEPTED
#
#   bash scripts/api.sh verify 9
#
# The ten routes that had no suite.
#
# An inventory of server.go against tests/ found 87 registered routes and
# ten that no suite mentions - not thinly covered, not covered. They are
# not obscure ones: the family message thread, the billing ledger, the
# centre dashboard, a guardian's consent, a personnel file and the public
# media route.
#
# THE FIRST GREP SAID BILLING WAS COVERED. a3 and a5 both matched the
# word - in a section heading and three comments, with no call anywhere.
# Searching for a word is not proof that a route is exercised, and this
# suite exists because of the gap that reading confirmed.
#
# WHAT IT HOLDS DOWN:
#
#   1. A GUARDIAN ID IN A PATH IS NOT AUTHORISATION. Six of these routes
#      take one. The rule - a family reaches its own row and no other -
#      lives in the policy on hbh.family_messages, and the check that
#      matters is the SECOND family: without a9_parent2 the suite could
#      not tell "reads their own thread" from "reads any thread".
#
#   2. AND THE REFUSAL IS AN EMPTY LIST, NOT AN ERROR. Row level security
#      filters; it does not raise. So the wrong family gets 200 and zero
#      rows, and a check that only asserts the status code passes on a
#      policy that has been deleted. Every isolation check here reads the
#      BODY.
#
#   3. THE PUBLIC ROUTE IS PUBLIC ON PURPOSE, AND ONLY THAT FAR.
#      /api/v1/site-media/{name} is the one route in this service with no
#      requireAuth - the marketing site fetches from it. So it is the one
#      route where a traversal would reach the disk of a service holding
#      clinical records.
#
#   4. BILLING IS A PERMISSION, AND THE SUBJECT OF THE REFUSAL IS STAFF.
#      a9_therapist is refused BILLING.VIEW, REQUEST.MANAGE and SITE.EDIT
#      while holding a staff account in the same centre - so no refusal
#      here can be passing merely because guardians are refused.
#
#   5. CONSENT IS GRANTED BY THE FAMILY OR BY THE DESK, AND BY NOBODY
#      ELSE. Tested from both sides: the parent's own grant must SUCCEED.
#      A gate proved only by its refusals is how a gate with no key stays
#      green - this project shipped one, and it refused every photograph
#      for a fortnight while its first check passed.
#
# The harness and the five rules it enforces are in tests/api/lib.sh.
# =====================================================================

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "============== api phase 9 - the routes nothing watched =============="
echo "base: $API_BASE"
echo

# =====================================================================
# FIXTURE - asserted by name, before any test runs
# =====================================================================
OUT="$(psqlf "$ROOT/tests/fixtures/a9_teardown.sql")"
RC=$?
if [ "$RC" != "0" ]; then chk fixture 'previous fixture removed' 1 "$OUT"; else chk fixture 'previous fixture removed' 0; fi

OUT="$(psqlf "$ROOT/tests/fixtures/a9_fixture.sql")"
RC=$?
if [ "$RC" != "0" ]; then chk fixture 'fixture applied' 1 "$OUT"; else chk fixture 'fixture applied' 0; fi

eq fixture 'service answers /healthz' '200' "$(req GET /healthz)"

G1="$(psqlq "SELECT g.guardian_id FROM hbh.guardians g JOIN hbh.users u ON u.user_id=g.user_id WHERE u.username='a9_parent1'")"
G2="$(psqlq "SELECT g.guardian_id FROM hbh.guardians g JOIN hbh.users u ON u.user_id=g.user_id WHERE u.username='a9_parent2'")"
CHILD="$(psqlq "SELECT child_id FROM hbh.children WHERE child_no='A9-A'")"
for v in G1 G2 CHILD; do
  eval "val=\$$v"
  ok_if fixture "$v is known" "$([ -n "$val" ] && echo 0 || echo 1)" "$v is empty"
done

ADMIN="$(staff_login a9_admin a9-admin-pw-123456)"
THERAPIST="$(staff_login a9_therapist a9-therapist-pw-123456)"
PARENT1="$(login 01500000192)"
PARENT2="$(login 01500000193)"
ok_if fixture 'the administrator signed in' "$([ -n "$ADMIN" ] && echo 0 || echo 1)" 'no token for a9_admin'
ok_if fixture 'the therapist signed in'     "$([ -n "$THERAPIST" ] && echo 0 || echo 1)" 'no token for a9_therapist'
ok_if fixture 'the first family signed in'  "$([ -n "$PARENT1" ] && echo 0 || echo 1)" 'no token for a9_parent1'
ok_if fixture 'the second family signed in' "$([ -n "$PARENT2" ] && echo 0 || echo 1)" 'no token for a9_parent2'

# EVERY TOKEN IS CONFIRMED TO BE THE ACCOUNT IT WAS ASKED FOR, and this
# is not ceremony. hbh.users has no unique index on mobile and
# hbh.request_otp takes `ORDER BY user_id LIMIT 1` - the oldest account
# holding that number. The first draft of this fixture reused four
# numbers already held by the dev seed accounts, and the code sent to
# a9_parent1's mobile signed in as dev_therapist: staff, a different
# person, silently. Every isolation check below would have been
# comparing the wrong two callers and passing.
for pair in "ADMIN a9_admin" "THERAPIST a9_therapist" "PARENT1 a9_parent1" "PARENT2 a9_parent2"; do
  set -- $pair
  eval "tok=\$$1"
  req GET /api/v1/me '' "$tok" >/dev/null
  eq fixture "the $2 token really is $2" "$2" "$(jstr "$BODY" username)"
done

# =====================================================================
# THE FAMILY THREAD
#
# The property: a guardian id in the path is not authorisation.
# =====================================================================
MSG='{"body":"رسالة من المركز إلى الأسرة","request_id":"11111111-1111-4111-8111-111111111111"}'

eq thread 'the desk writes to a family' '201' \
  "$(req POST "/api/v1/family-messages/$G1" "$MSG" "$ADMIN")"
MSG_ID="$(jnum "$BODY" message_id)"
ok_if thread 'and the message has an id' "$([ -n "$MSG_ID" ] && echo 0 || echo 1)" 'no message_id returned'

# The same request_id twice is ONE message. A phone on a bad connection
# retries, and a duplicated message in a clinical thread is a record of
# something that was said once and appears twice.
eq thread 'the same request_id writes nothing new' '201' \
  "$(req POST "/api/v1/family-messages/$G1" "$MSG" "$ADMIN")"
eq thread 'and returns the SAME message' "$MSG_ID" "$(jnum "$BODY" message_id)"
eq thread 'exactly one message on the thread' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.family_messages WHERE guardian_id=$G1")"

# The Arabic survived. It goes through a file in req(), never on the
# command line: curl here is a native Windows binary and MSYS converts
# its argv to the ANSI codepage, so Arabic passed as an argument is
# stored as a row of question marks and nothing reports it.
eq thread 'the Arabic was stored, not mangled' 't' \
  "$(psqlq "SELECT body_ar NOT LIKE '%?%' AND length(body_ar) > 10 FROM hbh.family_messages WHERE guardian_id=$G1")"

eq thread 'the family reads its own thread' '200' \
  "$(req GET "/api/v1/family-messages/$G1" '' "$PARENT1")"
eq thread 'and the message is there' '1' "$(jcount "$BODY" message_id)"
eq thread 'and is marked as not theirs' 'false' "$(jbool "$BODY" mine)"

# THE CHECK THIS SUITE WAS WRITTEN FOR. The other family is a real
# family of the same centre, so the centre rule cannot be what refuses
# them - only the policy can.
eq thread 'ANOTHER family gets 200 and NOTHING' '200' \
  "$(req GET "/api/v1/family-messages/$G1" '' "$PARENT2")"
eq thread 'not one message leaked' '0' "$(jcount "$BODY" message_id)"

# Staff without REQUEST.MANAGE are outside it too. A therapist is not a
# stranger to this centre, which is what makes the check worth having.
eq thread 'staff without REQUEST.MANAGE see nothing' '200' \
  "$(req GET "/api/v1/family-messages/$G1" '' "$THERAPIST")"
eq thread 'and nothing leaked to them either' '0' "$(jcount "$BODY" message_id)"

eq thread 'an anonymous caller is turned away' '401' \
  "$(req GET "/api/v1/family-messages/$G1")"

# Writing into somebody else's thread is refused outright rather than
# filtered - the INSERT has a policy of its own.
eq thread 'another family may not write into it' '403' \
  "$(req POST "/api/v1/family-messages/$G1" "$MSG" "$PARENT2")"
eq thread 'and the thread is still one message' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.family_messages WHERE guardian_id=$G1")"

eq thread 'a body of spaces is not a message' '400' \
  "$(req POST "/api/v1/family-messages/$G1" '{"body":"   ","request_id":"22222222-2222-4222-8222-222222222222"}' "$ADMIN")"
eq thread 'and a request_id must be a uuid' '400' \
  "$(req POST "/api/v1/family-messages/$G1" '{"body":"مرحبا","request_id":"not-a-uuid"}' "$ADMIN")"
eq thread 'a guardian id must be a number' '400' \
  "$(req GET "/api/v1/family-messages/abc" '' "$ADMIN")"

# Read marking is per USER, not per thread: the policy on
# family_message_reads is user_id = current_user_id().
eq thread 'the family marks the thread read' '200' \
  "$(req POST "/api/v1/family-messages/$G1/read" "{\"message_id\":$MSG_ID}" "$PARENT1")"
eq thread 'message_id 0 is refused' '400' \
  "$(req POST "/api/v1/family-messages/$G1/read" '{"message_id":0}' "$PARENT1")"
eq thread 'the read mark belongs to that user alone' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.family_message_reads r JOIN hbh.users u ON u.user_id=r.user_id WHERE r.guardian_id=$G1 AND u.username='a9_parent1'")"

# =====================================================================
# THE CONTACT LIST
# =====================================================================
eq contacts 'the desk sees the families' '200' "$(req GET /api/v1/family-contacts '' "$ADMIN")"
eq contacts 'including this one' 'yes' "$(grep -q "\"guardian_id\":$G1" "$BODY" && echo yes || echo no)"

# A family sees ITSELF and nothing else. The list is the same endpoint
# for both, which is exactly why it needs checking from both sides.
eq contacts 'a family sees exactly one row - its own' '200' \
  "$(req GET /api/v1/family-contacts '' "$PARENT1")"
eq contacts 'one row' '1' "$(jcount "$BODY" guardian_id)"
eq contacts 'and it is theirs' 'yes' "$(grep -q "\"guardian_id\":$G1" "$BODY" && echo yes || echo no)"
eq contacts 'the unread count went to zero after the read' '0' "$(jnum "$BODY" unread)"

eq contacts 'staff without REQUEST.MANAGE see no families' '200' \
  "$(req GET /api/v1/family-contacts '' "$THERAPIST")"
eq contacts 'and the list is empty' '0' "$(jcount "$BODY" guardian_id)"
eq contacts 'an over-long search is refused' '400' \
  "$(req GET "/api/v1/family-contacts?q=$(printf 'ا%.0s' $(seq 1 101))" '' "$ADMIN")"
eq contacts 'an anonymous caller is turned away' '401' "$(req GET /api/v1/family-contacts)"

# =====================================================================
# BILLING - a permission, and the refusal subject is staff
# =====================================================================
eq billing 'the desk reads the summary' '200' "$(req GET /api/v1/billing/summary '' "$ADMIN")"
eq billing 'staff without BILLING.VIEW are refused' '403' \
  "$(req GET /api/v1/billing/summary '' "$THERAPIST")"
eq billing 'and told it is a permission' 'FORBIDDEN' "$(jstr "$BODY" code)"
eq billing 'a family may not read the centre ledger' '403' \
  "$(req GET /api/v1/billing/summary '' "$PARENT1")"
eq billing 'an anonymous caller is turned away' '401' "$(req GET /api/v1/billing/summary)"

eq billing 'the ledger needs to be told which one' '400' \
  "$(req GET /api/v1/billing/ledger '' "$ADMIN")"
eq billing 'an invented kind is refused' '400' \
  "$(req GET "/api/v1/billing/ledger?kind=secrets" '' "$ADMIN")"
for kind in payments packages balances; do
  eq billing "the $kind ledger answers" '200' \
    "$(req GET "/api/v1/billing/ledger?kind=$kind" '' "$ADMIN")"
done
eq billing 'the page size is fixed by the server' '25' "$(jnum "$BODY" limit)"
eq billing 'page 0 does not exist' '400' \
  "$(req GET "/api/v1/billing/ledger?kind=payments&page=0" '' "$ADMIN")"
eq billing 'and neither does page 100001' '400' \
  "$(req GET "/api/v1/billing/ledger?kind=payments&page=100001" '' "$ADMIN")"
eq billing 'an over-long search is refused' '400' \
  "$(req GET "/api/v1/billing/ledger?kind=payments&q=$(printf 'a%.0s' $(seq 1 401))" '' "$ADMIN")"
eq billing 'the ledger asks the same permission' '403' \
  "$(req GET "/api/v1/billing/ledger?kind=payments" '' "$THERAPIST")"

# =====================================================================
# THE DASHBOARD
# =====================================================================
eq dash 'the console reads its metrics' '200' "$(req GET /api/v1/dashboard/metrics '' "$ADMIN")"
eq dash 'an anonymous caller reads nothing' '401' "$(req GET /api/v1/dashboard/metrics)"

# =====================================================================
# CONSENT - proved from BOTH sides
# =====================================================================
LIVE="{\"consent_type\":\"LIVE_VIEW\",\"child_id\":$CHILD,\"text_version\":\"v1\"}"

# THE ACCEPT SIDE FIRST, deliberately. A gate whose refusals all pass
# and whose accept was never tried is how this project shipped a consent
# check that refused every photograph for a fortnight while its first
# assertion stayed green.
eq consent 'the FAMILY may record its own consent' '201' \
  "$(req POST "/api/v1/guardians/$G1/consent" "$LIVE" "$PARENT1")"
eq consent 'and the row is on the record' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.consents WHERE guardian_id=$G1 AND consent_type='LIVE_VIEW' AND granted_flg")"

eq consent 'the desk may record it too' '201' \
  "$(req POST "/api/v1/guardians/$G1/consent" "{\"consent_type\":\"PHOTO_USE\",\"child_id\":$CHILD,\"text_version\":\"v1\"}" "$ADMIN")"

eq consent 'ANOTHER family may not consent for this one' '409' \
  "$(req POST "/api/v1/guardians/$G1/consent" "$LIVE" "$PARENT2")"
eq consent 'and a therapist may not either' '409' \
  "$(req POST "/api/v1/guardians/$G1/consent" "$LIVE" "$THERAPIST")"

eq consent 'a consent type must be named' '400' \
  "$(req POST "/api/v1/guardians/$G1/consent" '{}' "$ADMIN")"
eq consent 'and names the field' 'REQUIRED' "$(jstr "$BODY" consent_type)"

# 'PHOTO' is not a consent type. It is the exact literal that made the
# photograph gate unopenable, and the schema refuses it rather than
# storing a fourth kind nothing will ever ask for.
#
# TWO CONSTRAINTS GUARD THIS COLUMN AND THEY ANSWER DIFFERENTLY, which
# is right and is asserted both ways here. One lists the three types;
# the other pairs each type with whether it names a child - LIVE_VIEW
# and PHOTO_USE are about a child, SMS_NOTIFY is about the household.
# So 'PHOTO' alone trips the list and reads as a bad field, while
# 'PHOTO' WITH a child trips the pairing first and reads as a refusal.
# Two mistakes, two answers: "that is not a type" and "that type does
# not take a child".
eq consent 'an invented consent type is refused' '400' \
  "$(req POST "/api/v1/guardians/$G1/consent" '{"consent_type":"PHOTO"}' "$ADMIN")"
eq consent 'and names the constraint' 'REFUSED' "$(jstr "$BODY" constraint)"
eq consent 'the same type WITH a child trips the pairing rule' '409' \
  "$(req POST "/api/v1/guardians/$G1/consent" "{\"consent_type\":\"PHOTO\",\"child_id\":$CHILD}" "$ADMIN")"
# The pairing rule is not about 'PHOTO' being unknown - a REAL type on
# the wrong side of it is refused identically. Without this the check
# above would pass on the list constraint and prove nothing about the
# pairing.
eq consent 'and so does a real type on the wrong side of it' '409' \
  "$(req POST "/api/v1/guardians/$G1/consent" "{\"consent_type\":\"SMS_NOTIFY\",\"child_id\":$CHILD}" "$ADMIN")"
eq consent 'no such row was written' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.consents WHERE guardian_id=$G1 AND consent_type IN ('PHOTO','SMS_NOTIFY')")"

eq consent 'the desk may withdraw it' '204' \
  "$(req DELETE "/api/v1/guardians/$G1/consent" "$LIVE" "$ADMIN")"
eq consent 'withdrawn, not deleted' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.consents WHERE guardian_id=$G1 AND consent_type='LIVE_VIEW' AND NOT granted_flg")"

# The trail is append-only and says what happened, both ways.
ok_if consent 'the grant and the withdrawal are both on the trail' \
  "$([ "$(psqlq "SELECT count(*) FROM hbh.consent_events e JOIN hbh.consents c ON c.consent_id=e.consent_id WHERE c.guardian_id=$G1")" -ge 2 ] && echo 0 || echo 1)" \
  'fewer than two consent events'

eq consent 'an anonymous caller may not consent' '401' \
  "$(req POST "/api/v1/guardians/$G1/consent" "$LIVE")"

# =====================================================================
# THE PUBLIC MEDIA ROUTE, AND THE PRIVATE FILE ROUTE
#
# These two sit next to each other on purpose. One is the only route in
# this service with no requireAuth; the other holds personnel files.
# =====================================================================
eq media 'a missing asset is a 404, not a listing' '404' \
  "$(req GET /api/v1/site-media/nope.png)"
for probe in '..%2f..%2fetc%2fpasswd' '.env' '..%5c..%5cwindows%5cwin.ini'; do
  eq media "the public route refuses '$probe'" '404' \
    "$(req GET "/api/v1/site-media/$probe")"
done

# A PATH THE MUX CLEANS ANSWERS 301 BEFORE THE HANDLER SEES IT, and the
# first version of this check read that redirect as a failure. It is
# not - but a redirect is only harmless if it lands back inside this
# route, so both halves are asserted: where it points, and what that
# place then says.
eq media 'a path needing cleaning is redirected, not served' '301' \
  "$(req GET '/api/v1/site-media/....//etc/passwd')"
eq media 'and the redirect stays inside the media route' 'yes' \
  "$(case "$(hdr Location)" in /api/v1/site-media/*) echo yes;; *) echo "no: $(hdr Location)";; esac)"
eq media 'and that destination serves nothing' '404' \
  "$(req GET "$(hdr Location)")"
eq media 'uploading needs SITE.EDIT' '403' \
  "$(req POST /api/v1/site-media '{"x":1}' "$THERAPIST")"
eq media 'and a family may not upload' '403' \
  "$(req POST /api/v1/site-media '{"x":1}' "$PARENT1")"

eq docs 'a personnel file needs an identity' '401' \
  "$(req GET /api/v1/staff-documents/1/file)"
eq docs 'and an unknown document is a 404' '404' \
  "$(req GET /api/v1/staff-documents/999999/file '' "$THERAPIST")"

# =====================================================================
# THE DOOR
# =====================================================================
eq door 'the app role cannot delete a message' '0' \
  "$(psqlq "SELECT count(*) FROM information_schema.role_table_grants WHERE grantee='hbh_app' AND table_schema='hbh' AND table_name IN ('family_messages','family_message_reads','consents','consent_events') AND privilege_type='DELETE'")"
eq door 'row level security is on for the thread' 't' \
  "$(psqlq "SELECT bool_and(relrowsecurity) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hbh' AND c.relname IN ('family_messages','family_message_reads')")"
eq door 'an anonymous connection reads no message' '0' \
  "$(psqlapp "SELECT count(*) FROM hbh.family_messages")"
eq door 'and no consent' '0' "$(psqlapp "SELECT count(*) FROM hbh.consents")"

# =====================================================================
# CLEANUP - a recorded check like any other
# =====================================================================
OUT="$(psqlf "$ROOT/tests/fixtures/a9_teardown.sql")"
RC=$?
if [ "$RC" != "0" ]; then chk cleanup 'fixture removed' 1 "$OUT"; else chk cleanup 'fixture removed' 0; fi
eq cleanup 'no message survived' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.family_messages WHERE guardian_id IN ($G1,$G2)")"
eq cleanup 'no consent survived' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.consents WHERE guardian_id IN ($G1,$G2)")"
eq cleanup 'and no duplicate mobile was left behind' '0' \
  "$(psqlq "SELECT count(*) FROM (SELECT mobile FROM hbh.users WHERE active_flg AND mobile IS NOT NULL GROUP BY mobile HAVING count(*)>1) d")"

verdict 'API PHASE 9'
