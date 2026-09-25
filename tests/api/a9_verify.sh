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

# 404 AND NOT 409, AND THE CHANGE WAS A LEAK BEING CLOSED.
#
# These two read '409' until 2026-09-12, and nobody had decided that:
# HB082 was one of twenty-one live codes businessRefusal never named, so
# the catch-all answered every one of them 'REFUSED'. The suite recorded
# what the fallback happened to return and went green on it - which is
# the whole failure mode of a test written after the code rather than
# against a rule.
#
# And 409 was the wrong answer in a way that mattered. A guardian is not
# staff and cannot be assumed to have mistyped: somebody walking guardian
# ids from a family account learns from a 409 that the row is REAL, and
# from a 404 nothing at all. The schema refuses to distinguish "no such
# guardian" from "not yours" - see the three messages behind HB082 - and
# now so does the answer.
eq consent 'ANOTHER family may not consent for this one' '404' \
  "$(req POST "/api/v1/guardians/$G1/consent" "$LIVE" "$PARENT2")"
eq consent 'and a therapist may not either' '404' \
  "$(req POST "/api/v1/guardians/$G1/consent" "$LIVE" "$THERAPIST")"

# The property, not the number. A refusal that says 404 still leaks if a
# guardian who EXISTS answers differently from one who does not, so the
# two are asked side by side and required to be identical - status and
# body both. This is what the 409 could never have passed.
eq consent 'a guardian that does not exist answers the same way' '404' \
  "$(req POST "/api/v1/guardians/999999999/consent" "$LIVE" "$PARENT2")"
# request_id is stripped because it is the one field that MUST differ -
# it is per-request by design. Everything else has to match.
strip_rid() { sed -E 's/,?"request_id":"[^"]*"//' "$BODY"; }
ABSENT_BODY="$(strip_rid)"
eq consent 'the real guardian is refused identically' '404' \
  "$(req POST "/api/v1/guardians/$G1/consent" "$LIVE" "$PARENT2")"
eq consent 'and the two bodies are indistinguishable' "$ABSENT_BODY" "$(strip_rid)"

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
#
# BOTH ARE 400 SINCE 2026-09-12, AND THE DISTINCTION MOVED RATHER THAN
# DIED. The pairing rule used to answer 409 only because HB080 fell to
# businessRefusal's catch-all; it is a malformed BODY - a type that takes
# no child, sent with a child - and no amount of waiting or retrying
# changes the answer, which is the one thing 409 is supposed to mean.
#
# The two mistakes still answer differently and that is asserted below:
# the list constraint NAMES a constraint, the pairing rule does not. The
# original intent of this block is intact; only the axis it is read on
# has changed, from the status to the body.
eq consent 'an invented consent type is refused' '400' \
  "$(req POST "/api/v1/guardians/$G1/consent" '{"consent_type":"PHOTO"}' "$ADMIN")"
eq consent 'and names the constraint' 'REFUSED' "$(jstr "$BODY" constraint)"
eq consent 'the same type WITH a child trips the pairing rule' '400' \
  "$(req POST "/api/v1/guardians/$G1/consent" "{\"consent_type\":\"PHOTO\",\"child_id\":$CHILD}" "$ADMIN")"
# The pairing rule is not about 'PHOTO' being unknown - a REAL type on
# the wrong side of it is refused identically. Without this the check
# above would pass on the list constraint and prove nothing about the
# pairing.
eq consent 'and so does a real type on the wrong side of it' '400' \
  "$(req POST "/api/v1/guardians/$G1/consent" "{\"consent_type\":\"SMS_NOTIFY\",\"child_id\":$CHILD}" "$ADMIN")"
# The axis the two mistakes are still told apart on. A bare '' here means
# no constraint was named, which is what a business rule refusing a body
# looks like - as against the list constraint above, which names one. If
# this ever reads 'REFUSED' the two have collapsed into one answer and
# the block above has stopped proving anything.
eq consent 'but the pairing rule names no constraint' '' "$(jstr "$BODY" constraint)"
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
# NOTIFICATIONS - the mailbox nothing was watching
#
# Two routes with no check anywhere in tests/: GET /api/v1/notifications
# and POST /api/v1/notifications/{id}/read. They were found by listing
# every registered route and asking which no suite so much as mentions -
# the same inventory that created this suite, run again and still
# finding something.
#
# THE RULE IS PER-USER AND NOT PER-CENTRE, which is why it belongs here
# rather than beside the family thread. The policy reads
#
#     center_id = current_center_id() AND active_flg
#                 AND user_id = current_user_id()
#
# so the second family is not refused by the centre check - they are in
# the same centre - and a check with only one family in it would pass on
# a policy that had lost its last clause entirely. And a notification
# carries clinical context by design: "a session note was published for
# your child". The wrong mailbox is the wrong child.
#
# THE ROWS ARE BUILT WITH A DIRECT INSERT, not by calling notify_guardians.
# The product function decides WHO is notified and writing that decision
# here would make the fixture depend on a rule this suite does not test;
# worse, it fans out to every guardian of a child, so the second family's
# isolation could be broken by the fixture itself rather than by the
# endpoint. State is built, behaviour is tested.
# =====================================================================
NTF1="$(psqlq "INSERT INTO hbh.notifications (center_id, user_id, kind_code, title_ar, body_ar)
                SELECT u.center_id, u.user_id, 'NOTE_PUBLISHED', 'إشعار الأسرة الأولى', 'نصّ'
                  FROM hbh.users u WHERE u.username='a9_parent1' RETURNING notification_id")"
NTF2="$(psqlq "INSERT INTO hbh.notifications (center_id, user_id, kind_code, title_ar, body_ar)
                SELECT u.center_id, u.user_id, 'NOTE_PUBLISHED', 'إشعار الأسرة الثانية', 'نصّ'
                  FROM hbh.users u WHERE u.username='a9_parent2' RETURNING notification_id")"
for v in NTF1 NTF2; do
  eval "val=\$$v"
  ok_if bell "$v is known" "$([ -n "$val" ] && echo 0 || echo 1)" "$v is empty"
done

# The accept side first, as everywhere else in this suite.
eq bell 'the family reads its own mailbox' '200' \
  "$(req GET /api/v1/notifications '' "$PARENT1")"
ok_if bell 'and its own notification is in it' \
  "$(grep -q "\"notification_id\":$NTF1" "$BODY" && echo 0 || echo 1)" \
  'the family cannot see its own notification'

# THE CHECK THIS SECTION EXISTS FOR. Row level security filters, it does
# not raise - so the wrong family gets 200 and the row is simply absent.
# Asserting the status alone would pass on a deleted policy.
eq bell 'the OTHER family also gets 200' '200' \
  "$(req GET /api/v1/notifications '' "$PARENT2")"
ok_if bell 'and the first family notification is NOT in it' \
  "$(grep -q "\"notification_id\":$NTF1" "$BODY" && echo 1 || echo 0)" \
  "notification $NTF1 leaked to another family"
ok_if bell 'while its own IS' \
  "$(grep -q "\"notification_id\":$NTF2" "$BODY" && echo 0 || echo 1)" \
  'the second family cannot see its own notification'

# Staff are not a special case here. a9_therapist holds a real staff
# account in this centre and still has no business in a family mailbox.
eq bell 'staff get 200 and not the family mailbox' '200' \
  "$(req GET /api/v1/notifications '' "$THERAPIST")"
ok_if bell 'and no family notification is in it' \
  "$(grep -qE "\"notification_id\":($NTF1|$NTF2)" "$BODY" && echo 1 || echo 0)" \
  'a family notification reached staff'

# Marking read. hbh.mark_notification_read is SECURITY DEFINER, so the
# policy is NOT what protects it - the ownership test lives in the
# function's WHERE clause. That makes this the more important of the two
# routes to watch: a policy is visible in pg_policy and a forgotten AND
# in a function body is not.
eq bell "another family may not mark this one read" '404' \
  "$(req POST "/api/v1/notifications/$NTF1/read" '' "$PARENT2")"
eq bell 'and it is still unread on the row' 't' \
  "$(psqlq "SELECT read_at IS NULL FROM hbh.notifications WHERE notification_id=$NTF1")"

eq bell 'the owner may' '204' \
  "$(req POST "/api/v1/notifications/$NTF1/read" '' "$PARENT1")"
eq bell 'and the row says so' 'f' \
  "$(psqlq "SELECT read_at IS NULL FROM hbh.notifications WHERE notification_id=$NTF1")"

# The second click is a 404 because the function matches on
# read_at IS NULL, so "already read" answers exactly like "not yours" and
# "no such row". That conflation is deliberate and worth pinning: it is
# what stops a caller learning which notification ids exist by trying
# them. If this ever answers 204 twice, the WHERE clause has been
# loosened and the oracle is open.
eq bell 'marking it again is refused, not silently repeated' '404' \
  "$(req POST "/api/v1/notifications/$NTF1/read" '' "$PARENT1")"

eq bell 'an anonymous caller has no mailbox' '401' "$(req GET /api/v1/notifications)"
eq bell 'and cannot mark anything read' '401' \
  "$(req POST "/api/v1/notifications/$NTF1/read")"

# =====================================================================
# THE PAIRS LIST - the third route nothing mentioned
#
# GET /api/v1/service-therapists feeds the booking screen one list of
# valid (service, therapist) pairs, so an incompatible combination
# cannot be expressed rather than merely being discouraged.
#
# WHAT THESE CHECKS DO NOT PROVE, SAID HERE SO NOBODY READS THEM AS
# PROVING IT. The rule that matters on this route is centre scoping, and
# this database has ONE centre. A fixture that cannot produce the second
# case cannot tell the two apart - so a check written here as "the list
# is only my centre's" would be green on a query with no centre clause
# at all. When a second centre exists in the dev data, that check belongs
# here and is the first thing to add.
#
# What IS provable: the door is shut to strangers, the list is not empty,
# and `total` is not a number the handler made up separately from the
# rows it sent - a count that drifts from its own payload is how a screen
# pages past the end of a list.
# =====================================================================
eq pairs 'a stranger gets nothing' '401' "$(req GET /api/v1/service-therapists)"

eq pairs 'a signed-in caller may read it' '200' \
  "$(req GET /api/v1/service-therapists '' "$PARENT1")"

# Not empty FIRST. Every assertion below this line is vacuous on an empty
# list - "no pair leaked" and "the count matches" are both true of
# nothing at all.
PAIR_N="$(jnum "$BODY" total)"
ok_if pairs 'and the list is not empty' \
  "$([ -n "$PAIR_N" ] && [ "$PAIR_N" -gt 0 ] 2>/dev/null && echo 0 || echo 1)" \
  "total is [${PAIR_N:-missing}] - every check below would pass on nothing"

eq pairs 'the count matches the rows actually sent' "$PAIR_N" \
  "$(jcount "$BODY" therapist_id)"
eq pairs 'and matches what the schema holds' "$PAIR_N" \
  "$(psqlq "SELECT count(*) FROM hbh.therapist_services ts
              JOIN hbh.services s   ON s.service_id   = ts.service_id
              JOIN hbh.therapists t ON t.therapist_id = ts.therapist_id
             WHERE ts.active_flg AND s.active_flg AND t.active_flg")"

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
