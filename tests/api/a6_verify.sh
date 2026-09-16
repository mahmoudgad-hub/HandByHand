#!/usr/bin/env bash
# =====================================================================
# Hand By Hand (new) - API PHASE 6 acceptance suite
#
# Must print:  API PHASE 6 ACCEPTED
#
#   bash scripts/api.sh verify 6
#
# Three things that live outside the clinical record: a family that is
# not a client yet, a question the centre asks them, and the service
# watching itself.
#
# The first is the reason this suite exists. Every other endpoint in
# this service refuses a caller with no token; POST /api/v1/enrolments
# answers one. So the suite spends its first section proving that the
# door which is open is open ONLY that far - the anonymous caller may
# submit and may not read, may not insert directly, and is never told
# WHY a submission was refused, because each of the three reasons
# discloses something: which centres exist, or that a mobile number is
# already known here.
#
# The suite then walks one application the whole way:
#
#   submit (no token) -> queue -> CONTACTED -> convert -> a family
#
# and checks the two rules that survive that walk: converting does not
# grant permission to watch a child (D-24), and a second application
# from a known mobile attaches to the parent already on file instead of
# duplicating them.
#
# The harness and the five rules it enforces are in tests/api/lib.sh.
# =====================================================================

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "============ api phase 6 - intake, the survey, the log ============"
echo "base: $API_BASE"
echo

# =====================================================================
# FIXTURE - asserted by name, before any test runs
# =====================================================================
OUT="$(psqlf "$ROOT/tests/fixtures/a6_teardown.sql")"
RC=$?
if [ "$RC" != "0" ]; then chk fixture 'previous fixture removed' 1 "$OUT"; else chk fixture 'previous fixture removed' 0; fi

OUT="$(psqlf "$ROOT/tests/fixtures/a6_fixture.sql")"
RC=$?
if [ "$RC" != "0" ]; then chk fixture 'fixture applied' 1 "$OUT"; else chk fixture 'fixture applied' 0; fi

# Every count against the request log is scoped to this instant. The
# table is append-only and shared with every other suite on this
# database, so an unscoped count succeeds once and fails forever after.
RUN_START="$(psqlq "SELECT now()")"
SVC="$(psqlq "SELECT service_id FROM hbh.services WHERE code='A6-OT'")"
SURVEY="$(psqlq "SELECT survey_id FROM hbh.nps_surveys WHERE code='A6-PERIOD'")"
FIXTURE_GUARDIAN="$(psqlq "SELECT g.guardian_id FROM hbh.guardians g JOIN hbh.users u ON u.user_id=g.user_id WHERE u.username='a6_parent'")"

for v in RUN_START SVC SURVEY FIXTURE_GUARDIAN; do
  eval "val=\$$v"
  ok_if fixture "$v is known" "$([ -n "$val" ] && echo 0 || echo 1)" "$v is empty"
done

eq fixture 'service answers /healthz' '200' "$(req GET /healthz)"

for m in 0018 0019 0020 0026; do
  eq fixture "migration $m is applied" 't' "$(psqlq "SELECT hbh.migration_applied('$m')")"
done

ADMIN="$(staff_login a6_admin a6-admin-pw-123456)"
RECEPTION="$(staff_login a6_reception a6-reception-pw-123456)"
PARENT="$(login 01500000062)"
ok_if fixture 'the administrator signed in' "$([ -n "$ADMIN" ] && echo 0 || echo 1)" 'no token for a6_admin'
ok_if fixture 'reception signed in'         "$([ -n "$RECEPTION" ] && echo 0 || echo 1)" 'no token for a6_reception'
ok_if fixture 'the guardian signed in'      "$([ -n "$PARENT" ] && echo 0 || echo 1)" 'no token for a6_parent'

# =====================================================================
# THE ANONYMOUS DOOR
#
# One endpoint in this service answers a caller with no token. These
# checks are about how far that goes.
# =====================================================================
APP1_BODY='{"center_code":"HBH","parent_name_ar":"أسرة الالتحاق الأولى","parent_mobile":"01500000063","child_name_ar":"طفل الالتحاق","child_birth_date":"2021-03-15","child_gender":"M","relationship_code":"MOTHER","main_concern_ar":"تأخر في النطق","preferred_contact_time":"مساءً"}'

eq anon 'an application is accepted with NO token' '201' "$(req POST /api/v1/enrolments "$APP1_BODY")"
APP1_NO="$(jstr "$BODY" application_no)"
ok_if anon 'the family is given an application number' "$([ -n "$APP1_NO" ] && echo 0 || echo 1)" 'no application_no in the body'
eq anon 'the answer carries no reason'         'no' "$(jhas "$BODY" reason)"
eq anon 'the answer carries no identifier'     'no' "$(jhas "$BODY" application_id)"
eq anon 'the row was written'                  '1'  "$(psqlq "SELECT count(*) FROM hbh.enrolment_applications WHERE parent_mobile=hbh.canonical_mobile('01500000063')")"
eq anon 'it starts in NEW'                     'NEW' "$(psqlq "SELECT status FROM hbh.enrolment_applications WHERE parent_mobile=hbh.canonical_mobile('01500000063')")"

# THE NUMBER IS STORED CANONICALISED, AND THIS IS THE ONE PLACE THAT SAYS SO.
#
# WHAT IT COST. trg_enr_mobile_canon rewrites parent_mobile to E.164 on
# the way in, so the form sends 01500000063 and the table holds
# +201500000063. a6_fixture.sql and a6_teardown.sql were updated to the
# new form; THIS FILE WAS NOT - and every lookup here read by the number
# the form had sent, found nothing, and left APP1 empty. Forty-nine
# checks failed, and not one of them named a mobile number: with an empty
# id the path became /api/v1/enrolments//convert, which ServeMux cleans
# and answers 301, so the suite reported a redirect where it expected a
# refusal. It read exactly like a broken route.
#
# Every lookup above now asks the schema what the number becomes rather
# than spelling it out - one rule, one place. But a suite that only ever
# asks the function can no longer NOTICE the function changing, so the
# literal is asserted here, once, deliberately. This line is the one that
# is supposed to fail the day the stored shape moves.
eq anon 'and the mobile is stored canonicalised, not as typed' '+201500000063' \
  "$(psqlq "SELECT parent_mobile FROM hbh.enrolment_applications WHERE parent_mobile=hbh.canonical_mobile('01500000063')")"
eq anon 'the address was recorded for the limit' 't' "$(psqlq "SELECT client_ip IS NOT NULL FROM hbh.enrolment_applications WHERE parent_mobile=hbh.canonical_mobile('01500000063')")"

# An unknown centre code. REJECTED must not travel: it would let anybody
# enumerate the centres on this installation by trying codes.
UNKNOWN='{"center_code":"NOPE","parent_name_ar":"أسرة","parent_mobile":"01500000063","child_name_ar":"طفل","child_birth_date":"2021-03-15","child_gender":"M"}'
eq anon 'an unknown centre is refused'          '400' "$(req POST /api/v1/enrolments "$UNKNOWN")"
eq anon 'and is not told that it was the centre' 'no' "$(jhas "$BODY" reason)"
eq anon 'and no row was written'                 '1' "$(psqlq "SELECT count(*) FROM hbh.enrolment_applications WHERE parent_mobile=hbh.canonical_mobile('01500000063')")"

eq anon 'a missing mobile is refused' '400' \
  "$(req POST /api/v1/enrolments '{"center_code":"HBH","parent_name_ar":"أسرة","parent_mobile":"","child_name_ar":"طفل","child_birth_date":"2021-03-15","child_gender":"M"}')"
eq anon 'and the field is named' 'parent_mobile' "$(jstr "$BODY" field)"

eq anon 'a birth date that is an instant is refused' '400' \
  "$(req POST /api/v1/enrolments '{"center_code":"HBH","parent_name_ar":"أسرة","parent_mobile":"01500000063","child_name_ar":"طفل","child_birth_date":"2021-03-15T00:00:00Z","child_gender":"M"}')"
eq anon 'and the field is named' 'child_birth_date (YYYY-MM-DD)' "$(jstr "$BODY" field)"

eq anon 'an unknown gender is refused' '400' \
  "$(req POST /api/v1/enrolments '{"center_code":"HBH","parent_name_ar":"أسرة","parent_mobile":"01500000063","child_name_ar":"طفل","child_birth_date":"2021-03-15","child_gender":"X"}')"
eq anon 'and the field is named' 'child_gender (M|F)' "$(jstr "$BODY" field)"

eq anon 'an unknown field is refused' '400' \
  "$(req POST /api/v1/enrolments '{"center_code":"HBH","parent_name_ar":"أسرة","parent_mobile":"01500000063","child_name_ar":"طفل","child_birth_date":"2021-03-15","child_gender":"M","center_id":1}')"

# The other half of the door: nothing may be READ without a token, and
# the table cannot be reached directly at all.
eq anon 'the queue needs a token' '401' "$(req GET /api/v1/enrolments)"
eq anon 'the single read needs a token' '401' "$(req GET /api/v1/enrolments/1)"
eq anon 'an anonymous connection reads no application' '0' \
  "$(psqlapp "SELECT count(*) FROM hbh.enrolment_applications")"

OUT="$(psqlapp "INSERT INTO hbh.enrolment_applications (center_id, application_no, parent_name_ar, parent_mobile, child_name_ar, child_birth_date, child_gender) VALUES (1,'X','x','01500000099','x',DATE '2020-01-01','M')")"
# A sentinel, because grep -q "" matches every line: an empty $OUT must
# read as a failure, not as a pass.
ok_if anon 'an anonymous connection cannot insert one' \
  "$(printf '%s' "${OUT:-EMPTY}" | grep -qi 'permission denied' && echo 0 || echo 1)" \
  "expected a permission refusal, got [$OUT]"

# =====================================================================
# THE PER-MOBILE LIMIT
#
# Three a day, from hbh.sys_params. The fourth is refused by the
# DATABASE and reaches the caller as 429 - the same shape as the
# transport limiter, deliberately: which of the two refused is not a
# stranger's business.
# =====================================================================
LIMIT_BODY='{"center_code":"HBH","parent_name_ar":"أسرة الحدّ","parent_mobile":"01500000064","child_name_ar":"طفل الحدّ","child_birth_date":"2020-01-01","child_gender":"F"}'
eq limit 'first application accepted'  '201' "$(req POST /api/v1/enrolments "$LIMIT_BODY")"
eq limit 'second application accepted' '201' "$(req POST /api/v1/enrolments "$LIMIT_BODY")"
eq limit 'third application accepted'  '201' "$(req POST /api/v1/enrolments "$LIMIT_BODY")"
eq limit 'the fourth is refused'       '429' "$(req POST /api/v1/enrolments "$LIMIT_BODY")"
eq limit 'and is not told which limit fired' 'no' "$(jhas "$BODY" reason)"
eq limit 'exactly three rows exist' '3' \
  "$(psqlq "SELECT count(*) FROM hbh.enrolment_applications WHERE parent_mobile=hbh.canonical_mobile('01500000064')")"
eq limit 'the refusal was recorded with its real reason' 't' \
  "$(psqlq "SELECT count(*) > 0 FROM hbh.audit_log WHERE action='DENY' AND detail LIKE 'ENROLMENT TOO_MANY%' AND changed_at >= '$RUN_START'")"

# THE ROWS ARE GIVEN BACK NOW, NOT AT CLEANUP - AND THE REASON IS THE
# OTHER LIMIT.
#
# ENROLMENT_MAX_PER_IP_HOUR is ten, counted against client_ip, and every
# request from this host arrives as the same address: 172.18.0.1. That
# bucket is therefore SHARED with every other session on this machine,
# with any hand-run curl, and with the end-to-end probe a migration does
# to prove itself. The suite cannot scope it - TRUST_PROXY is false, so
# X-Forwarded-For is ignored and a test cannot choose its own address,
# which is the correct posture and not something to relax for a test.
#
# WHAT IT COST. The three rows above sat in the bucket for the rest of
# the run, and the neighbours had already used seven. `reuse` and
# `siblings` then got 429 where they expected 201 - eighteen failures
# whose first line said "a known family applies again: expected 201, got
# 429", which reads as the per-mobile limit misfiring on a mobile that
# had submitted once. It was the per-IP limit, and no failure named it.
# The suite had passed forty minutes earlier with the same code, on a
# quieter bucket.
#
# So the suite stops holding what it no longer needs. These rows have
# already proved everything they were written to prove. Deleted BY THE
# MOBILE THIS SECTION OWNS - never by client_ip, which would reach into
# the rows of whoever else is on this host, and never by resemblance.
psqlq "DELETE FROM hbh.enrolment_applications
        WHERE parent_mobile = hbh.canonical_mobile('01500000064')" >/dev/null
eq limit 'and the section gives its slots back' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.enrolment_applications WHERE parent_mobile=hbh.canonical_mobile('01500000064')")"

# AND THE PRECONDITION IS ASSERTED BY NAME, because it cannot be
# guaranteed. If the shared bucket is full when the sections below run,
# they will be refused and every one of their failures will describe the
# wrong rule. Better to say it once, here, in the words of the thing that
# actually happened.
IP_USED="$(psqlq "SELECT count(*) FROM hbh.enrolment_applications
                   WHERE client_ip='172.18.0.1' AND submitted_at > now() - interval '1 hour'")"
IP_CAP="$(psqlq "SELECT hbh.param((SELECT center_id FROM hbh.centers WHERE code='HBH'),
                                  'ENROLMENT_MAX_PER_IP_HOUR','10')::integer")"
ok_if limit 'the shared per-IP bucket still has room for what follows' \
  "$([ -n "$IP_USED" ] && [ -n "$IP_CAP" ] && [ "$((IP_CAP - IP_USED))" -ge 4 ] && echo 0 || echo 1)" \
  "only $((${IP_CAP:-0} - ${IP_USED:-0})) of ${IP_CAP:-?} per-IP slots left - another session or a hand-run probe submitted enrolments from this host within the hour, so the sections below will be refused for a reason that has nothing to do with what they test"

APP1="$(psqlq "SELECT application_id FROM hbh.enrolment_applications WHERE parent_mobile=hbh.canonical_mobile('01500000063')")"
ok_if queue 'the application id is known' "$([ -n "$APP1" ] && echo 0 || echo 1)" 'no application_id'

# =====================================================================
# THE QUEUE
# =====================================================================
eq queue 'the administrator sees the queue' '200' "$(req GET /api/v1/enrolments '' "$ADMIN")"
eq queue 'the envelope carries a total'  'yes' "$(jhas "$BODY" total)"
eq queue 'the envelope carries a limit'  'yes' "$(jhas "$BODY" limit)"
eq queue 'the envelope carries an offset' 'yes' "$(jhas "$BODY" offset)"
ok_if queue 'the new application is in it' \
  "$(grep -q "\"$APP1_NO\"" "$BODY" && echo 0 || echo 1)" "application $APP1_NO is not in the queue"
eq queue 'the queue does not carry the address' 'no' "$(jhas "$BODY" client_ip)"

eq queue 'reception sees the queue too' '200' "$(req GET /api/v1/enrolments '' "$RECEPTION")"
ok_if queue 'and sees the same application' \
  "$(grep -q "\"$APP1_NO\"" "$BODY" && echo 0 || echo 1)" 'reception cannot see the queue it works'

eq queue 'a guardian is answered' '200' "$(req GET /api/v1/enrolments '' "$PARENT")"
eq queue 'and sees nothing in it'  '0'  "$(jnum "$BODY" total)"

eq queue 'one application reads back' '200' "$(req GET "/api/v1/enrolments/$APP1" '' "$ADMIN")"
eq queue 'it is the right one' "$APP1_NO" "$(jstr "$BODY" application_no)"
eq queue 'the birth date is a day, not an instant' '2021-03-15' "$(jstr "$BODY" child_birth_date)"
eq queue 'the single read hides the address too' 'no' "$(jhas "$BODY" client_ip)"
eq queue 'an unknown application is 404' '404' "$(req GET /api/v1/enrolments/99999999 '' "$ADMIN")"
eq queue 'a guardian cannot read one'    '404' "$(req GET "/api/v1/enrolments/$APP1" '' "$PARENT")"

eq queue 'status=NEW finds it' '200' "$(req GET '/api/v1/enrolments?status=NEW' '' "$ADMIN")"
ok_if queue 'and the filter is applied' \
  "$(grep -q "\"$APP1_NO\"" "$BODY" && echo 0 || echo 1)" 'the NEW filter hid a NEW application'
# Scoped to THIS suite's application, not to a total.
#
# A count over the whole centre is a number this suite does not own -
# another session working the same database enrols a family and the
# check goes red for a reason that has nothing to do with the filter. The
# question being asked is "is MY application excluded", so that is the
# question the check asks.
eq queue 'status=ENROLLED is a real filter' '200' "$(req GET '/api/v1/enrolments?status=ENROLLED' '' "$ADMIN")"
ok_if queue 'and this NEW application is not in it' \
  "$(grep -q "\"$APP1_NO\"" "$BODY" && echo 1 || echo 0)" \
  'a NEW application appeared under status=ENROLLED'

eq queue 'limit=0 is refused' '400' "$(req GET '/api/v1/enrolments?limit=0' '' "$ADMIN")"
eq queue 'and names the field'  'limit' "$(jstr "$BODY" field)"
eq queue 'page=0 is refused'   '400' "$(req GET '/api/v1/enrolments?page=0' '' "$ADMIN")"
eq queue 'and names the field'  'page' "$(jstr "$BODY" field)"
eq queue 'a page beyond the end is empty, not an error' '200' "$(req GET '/api/v1/enrolments?page=999' '' "$ADMIN")"

# =====================================================================
# THE STATE MACHINE, AND CONVERSION
#
# A family asks and the centre answers. The order below is the order the
# rules fire in, and each negative check names the code it expects.
# =====================================================================
eq convert 'converting a NEW application is refused' '409' \
  "$(req POST "/api/v1/enrolments/$APP1/convert" '' "$ADMIN")"
eq convert 'and says the transition is illegal' 'ILLEGAL_TRANSITION' "$(jstr "$BODY" code)"

eq convert 'a guardian cannot convert' '403' \
  "$(req POST "/api/v1/enrolments/$APP1/convert" '' "$PARENT")"
eq convert 'and is told it is forbidden' 'FORBIDDEN' "$(jstr "$BODY" code)"

eq state 'NEW straight to ENROLLED is refused' '409' \
  "$(req PATCH "/api/v1/enrolments/$APP1" '{"status":"ENROLLED"}' "$ADMIN")"
eq state 'and says the transition is illegal' 'ILLEGAL_TRANSITION' "$(jstr "$BODY" code)"

# The check the whole batch turns on. Since writing was opened, a policy
# refusal is no longer an error: the grant exists, so a caller the
# policy does not admit updates ZERO ROWS and Postgres reports success.
# A handler that did not count rows would answer 204 here and the
# application would not have moved.
eq state 'a guardian cannot move an application' '404' \
  "$(req PATCH "/api/v1/enrolments/$APP1" '{"status":"CONTACTED"}' "$PARENT")"
eq state 'and nothing moved' 'NEW' \
  "$(psqlq "SELECT status FROM hbh.enrolment_applications WHERE application_id=$APP1")"

eq state 'reception records the phone call' '204' \
  "$(req PATCH "/api/v1/enrolments/$APP1" '{"status":"CONTACTED","note_ar":"تم الاتصال بالأسرة"}' "$RECEPTION")"
eq state 'the application is CONTACTED' 'CONTACTED' \
  "$(psqlq "SELECT status FROM hbh.enrolment_applications WHERE application_id=$APP1")"
eq state 'the note was kept' 't' \
  "$(psqlq "SELECT contact_note_ar IS NOT NULL FROM hbh.enrolment_applications WHERE application_id=$APP1")"
eq state 'and the time of contact was stamped' 't' \
  "$(psqlq "SELECT contacted_at IS NOT NULL FROM hbh.enrolment_applications WHERE application_id=$APP1")"

eq convert 'the application becomes a family' '201' \
  "$(req POST "/api/v1/enrolments/$APP1/convert" '{"note_ar":"تم القبول"}' "$ADMIN")"
NEW_CHILD="$(jnum "$BODY" child_id)"
NEW_GUARDIAN="$(jnum "$BODY" guardian_id)"
eq convert 'the new child is numbered' 'yes' "$(jhas "$BODY" child_no)"
ok_if convert 'a child identifier came back' "$([ -n "$NEW_CHILD" ] && echo 0 || echo 1)" 'no child_id'
eq convert 'the child exists' '1' "$(psqlq "SELECT count(*) FROM hbh.children WHERE child_id=${NEW_CHILD:-0}")"
eq convert 'the guardian is linked to them' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.guardian_children WHERE child_id=${NEW_CHILD:-0} AND guardian_id=${NEW_GUARDIAN:-0}")"

# D-24. Filling in a form is not consent to watch a child in a therapy
# session, and the most sensitive switch in this system must not be
# turned on by an intake clerk pressing one button.
eq convert 'watching the child is NOT granted by conversion' 'f' \
  "$(psqlq "SELECT can_view_live_flg FROM hbh.guardian_children WHERE child_id=${NEW_CHILD:-0} AND guardian_id=${NEW_GUARDIAN:-0}")"

eq convert 'the application is ENROLLED' 'ENROLLED' \
  "$(psqlq "SELECT status FROM hbh.enrolment_applications WHERE application_id=$APP1")"
eq convert 'and remembers what it became' 't' \
  "$(psqlq "SELECT converted_child_id IS NOT NULL AND converted_guardian_id IS NOT NULL FROM hbh.enrolment_applications WHERE application_id=$APP1")"
eq convert 'converting twice is refused' '409' \
  "$(req POST "/api/v1/enrolments/$APP1/convert" '' "$ADMIN")"
eq convert 'and one child was created, not two' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.children c JOIN hbh.enrolment_applications e ON e.converted_child_id=c.child_id WHERE e.application_id=$APP1")"

# The second application, from a mobile this centre already knows. It
# must attach to the parent on file: a family with two children is one
# family, and a duplicate parent record splits their history in half.
REUSE='{"center_code":"HBH","parent_name_ar":"وليّ الأمر — ستة","parent_mobile":"01500000062","child_name_ar":"الطفل الثاني","child_birth_date":"2022-08-08","child_gender":"F"}'
eq reuse 'a known family applies again' '201' "$(req POST /api/v1/enrolments "$REUSE")"
APP2="$(psqlq "SELECT application_id FROM hbh.enrolment_applications WHERE parent_mobile=hbh.canonical_mobile('01500000062')")"
eq reuse 'reception contacts them' '204' \
  "$(req PATCH "/api/v1/enrolments/$APP2" '{"status":"CONTACTED"}' "$RECEPTION")"
eq reuse 'and the application converts' '201' \
  "$(req POST "/api/v1/enrolments/$APP2/convert" '' "$ADMIN")"
eq reuse 'to the guardian already on file' "$FIXTURE_GUARDIAN" "$(jnum "$BODY" guardian_id)"
eq reuse 'who now has two children' '2' \
  "$(psqlq "SELECT count(*) FROM hbh.guardian_children WHERE guardian_id=$FIXTURE_GUARDIAN")"
eq reuse 'and there is still one guardian on that mobile' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.guardians WHERE mobile=hbh.canonical_mobile('01500000062') AND active_flg")"

# =====================================================================
# A FAMILY WITH TWO CHILDREN
#
# One application is one child, so a family with two sends two. That is
# the right shape - each child needs their own birth date, their own
# main concern, and eventually their own file - and conversion attaches
# the second child to the parent already on record.
#
# THE HAZARD IS ON THE SCREEN. Reception sees two rows carrying one
# mobile number, and the queue has a DUPLICATE status sitting right
# there. Marking the second one duplicate is the obvious mistake, and it
# leaves a real child unenrolled with no error anywhere: the row is
# closed, the family was told nothing, and nobody is looking for it.
#
# So the row says "siblings" where it would otherwise say nothing.
# =====================================================================
SIB='{"center_code":"HBH","parent_name_ar":"أسرة الالتحاق الأولى","parent_mobile":"01500000063","child_name_ar":"الأخ الأصغر","child_birth_date":"2023-05-05","child_gender":"M"}'
eq siblings 'the same family applies for a second child' '201' \
  "$(req POST /api/v1/enrolments "$SIB")"
SIB_ID="$(psqlq "SELECT application_id FROM hbh.enrolment_applications
                 WHERE parent_mobile=hbh.canonical_mobile('01500000063') AND child_name_ar='الأخ الأصغر'")"
ok_if siblings 'the second application exists' "$([ -n "$SIB_ID" ] && echo 0 || echo 1)" 'no second application'
eq siblings 'and it is a separate row, not a merge' '2' \
  "$(psqlq "SELECT count(*) FROM hbh.enrolment_applications WHERE parent_mobile=hbh.canonical_mobile('01500000063')")"

eq siblings 'the queue row says there is a sibling' '200' \
  "$(req GET "/api/v1/enrolments/$SIB_ID" '' "$ADMIN")"
eq siblings 'and counts it'  '1' "$(jnum "$BODY" sibling_applications)"
# The first application from this mobile was already converted above, so
# the screen can say "this family is already with us" rather than
# leaving reception to guess from a phone number.
eq siblings 'and knows the family is already here' 'true' "$(jbool "$BODY" family_already_here)"

# The child converted earlier is NOT a sibling count of itself.
eq siblings 'an only child has no siblings' '200' \
  "$(req GET "/api/v1/enrolments/$APP2" '' "$ADMIN")"
eq siblings 'and the count says zero' '0' "$(jnum "$BODY" sibling_applications)"

eq siblings 'the second child converts to the SAME parent' '204' \
  "$(req PATCH "/api/v1/enrolments/$SIB_ID" '{"status":"CONTACTED"}' "$RECEPTION")"
eq siblings 'and conversion attaches rather than duplicates' '201' \
  "$(req POST "/api/v1/enrolments/$SIB_ID/convert" '' "$ADMIN")"
eq siblings 'to the guardian the first child created' "$NEW_GUARDIAN" "$(jnum "$BODY" guardian_id)"
eq siblings 'who now has two children'  '2' \
  "$(psqlq "SELECT count(*) FROM hbh.guardian_children WHERE guardian_id=${NEW_GUARDIAN:-0}")"
eq siblings 'and is still one person on that mobile' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.guardians WHERE mobile=hbh.canonical_mobile('01500000063') AND active_flg")"
eq siblings 'each child kept their own birth date' '2' \
  "$(psqlq "SELECT count(DISTINCT birth_date) FROM hbh.children c
            JOIN hbh.guardian_children gc ON gc.child_id = c.child_id
            WHERE gc.guardian_id = ${NEW_GUARDIAN:-0}")"
# D-24 again, per child. A consent recorded for one sibling is not a
# consent for the other, and conversion grants neither.
eq siblings 'and neither child may be watched' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.guardian_children
            WHERE guardian_id = ${NEW_GUARDIAN:-0} AND can_view_live_flg")"

# =====================================================================
# THE SATISFACTION SURVEY
# =====================================================================
eq nps 'the portal asks what is due' '200' "$(req GET /api/v1/nps/due '' "$PARENT")"
eq nps 'a question is due' "$SURVEY" "$(jnum "$BODY" survey_id)"
ok_if nps 'the question text comes from the database' \
  "$([ -n "$(jstr "$BODY" question_ar)" ] && echo 0 || echo 1)" 'no question_ar'
ok_if nps 'and so does the follow-up' \
  "$([ -n "$(jstr "$BODY" followup_question_ar)" ] && echo 0 || echo 1)" 'no followup_question_ar'

eq nps 'a staff account is asked nothing' '200' "$(req GET /api/v1/nps/due '' "$ADMIN")"
eq nps 'because the survey is for families' 'no' "$(jhas "$BODY" survey_id)"

eq nps 'a score above ten is refused' '400' \
  "$(req POST "/api/v1/nps/$SURVEY/response" '{"score":11}' "$PARENT")"
eq nps 'a negative score is refused' '400' \
  "$(req POST "/api/v1/nps/$SURVEY/response" '{"score":-1}' "$PARENT")"
eq nps 'an answer with no score is refused' '400' \
  "$(req POST "/api/v1/nps/$SURVEY/response" '{"comment_ar":"ممتاز"}' "$PARENT")"
eq nps 'and the field is named' '0..10' "$(jstr "$BODY" score)"
eq nps 'nothing was recorded by the refusals' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.nps_responses WHERE survey_id=$SURVEY")"

eq nps 'the family answers' '204' \
  "$(req POST "/api/v1/nps/$SURVEY/response" '{"score":9,"comment_ar":"فريق متعاون"}' "$PARENT")"
eq nps 'the score was recorded' '9' \
  "$(psqlq "SELECT score FROM hbh.nps_responses WHERE survey_id=$SURVEY AND NOT skipped_flg")"
eq nps 'and it is not marked as a dismissal' 'f' \
  "$(psqlq "SELECT skipped_flg FROM hbh.nps_responses WHERE survey_id=$SURVEY AND score=9")"

# The cooldown. Without this the same question returns on every page
# load, which is how a polite question becomes a nag.
eq nps 'the question does not come back' '200' "$(req GET /api/v1/nps/due '' "$PARENT")"
eq nps 'the cooldown holds' 'no' "$(jhas "$BODY" survey_id)"

eq nps 'a dismissal is recorded too' '204' "$(req POST "/api/v1/nps/$SURVEY/skip" '' "$PARENT")"
eq nps 'and is stored as a skip with no score' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.nps_responses WHERE survey_id=$SURVEY AND skipped_flg AND score IS NULL")"

# The configuration is data an administrator edits, not code.
eq nps 'an administrator creates a survey' '201' \
  "$(req POST /api/v1/nps-surveys '{"code":"A6-NEW","name_ar":"استبيان جديد","question_ar":"كيف كانت زيارتك؟","audience":"ALL","trigger_kind":"PERIOD","period_days":30,"cooldown_days":60}' "$ADMIN")"
eq nps 'a survey that could never fire is refused' '400' \
  "$(req POST /api/v1/nps-surveys '{"code":"A6-DEAD","name_ar":"استبيان ميت","question_ar":"؟","audience":"ALL","trigger_kind":"PERIOD","cooldown_days":30}' "$ADMIN")"
eq nps 'reception cannot configure surveys' '403' \
  "$(req POST /api/v1/nps-surveys '{"code":"A6-REC","name_ar":"استبيان الاستقبال","question_ar":"؟","audience":"ALL","trigger_kind":"PERIOD","period_days":30}' "$RECEPTION")"
eq nps 'and nothing was written' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.nps_surveys WHERE code IN ('A6-DEAD','A6-REC')")"

eq nps 'the results read back' '200' "$(req GET /api/v1/nps/summary '' "$ADMIN")"
eq nps 'the summary carries the score itself' 'yes' "$(jhas "$BODY" nps)"
eq nps 'and the mean beside it'               'yes' "$(jhas "$BODY" mean_score)"
eq nps 'the answer was counted'               'yes' "$(jhas "$BODY" answered_cnt)"

# =====================================================================
# THE SERVICE WATCHING ITSELF
#
# Every request above wrote a row. These checks are about what is in
# those rows and who may read them.
# =====================================================================
req GET /api/v1/there-is-no-such-endpoint '' "$ADMIN" >/dev/null

eq log 'the administrator reads the health view' '200' "$(req GET /api/v1/ops/health '' "$ADMIN")"
ok_if log 'and there is traffic in it' \
  "$([ "$(jnum "$BODY" total)" -gt 0 ] 2>/dev/null && echo 0 || echo 1)" 'the health view is empty'

# OPS.VIEW belongs to the centre administrator alone. Reception works
# the intake queue and does not read the service's own telemetry - and
# the refusal is an EMPTY LIST rather than a 403, because the policy
# filters rows and never endpoints.
eq log 'reception is answered'   '200' "$(req GET /api/v1/ops/health '' "$RECEPTION")"
eq log 'and sees no telemetry'   '0'   "$(jnum "$BODY" total)"
eq log 'a guardian is answered'  '200' "$(req GET /api/v1/ops/health '' "$PARENT")"
eq log 'and sees no telemetry'   '0'   "$(jnum "$BODY" total)"

eq log 'the errors read back'  '200' "$(req GET /api/v1/ops/errors '' "$ADMIN")"
ok_if log 'and the refusals above are in them' \
  "$(grep -q 'VALIDATION' "$BODY" && echo 0 || echo 1)" 'no VALIDATION error was logged'
eq log 'the activity reads back' '200' "$(req GET /api/v1/ops/activity '' "$ADMIN")"
ok_if log 'and names who was working' \
  "$(grep -q 'a6_admin' "$BODY" && echo 0 || echo 1)" 'a6_admin is not in the activity view'
eq log 'reception sees no activity' '200' "$(req GET /api/v1/ops/activity '' "$RECEPTION")"
eq log 'and the list is empty'      '0'   "$(jnum "$BODY" total)"

# The route is a TEMPLATE. A log grouped by path gives one row per
# child and tells nobody which endpoint is slow - and it puts a stream
# of identifiers on a screen an operator reads.
eq log 'no logged route carries an identifier' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.request_log WHERE occurred_at >= '$RUN_START' AND route ~ '/[0-9]+'")"
eq log 'the parameterised route was recorded as a template' 't' \
  "$(psqlq "SELECT count(*) > 0 FROM hbh.request_log WHERE occurred_at >= '$RUN_START' AND route = '/api/v1/enrolments/{application_id}'")"
eq log 'a request that matched no route is filed under a sentinel' 't' \
  "$(psqlq "SELECT count(*) > 0 FROM hbh.request_log WHERE occurred_at >= '$RUN_START' AND route = '(unrouted)'")"

eq log 'the anonymous submission was filed against nobody' 't' \
  "$(psqlq "SELECT count(*) > 0 FROM hbh.request_log WHERE occurred_at >= '$RUN_START' AND route='/api/v1/enrolments' AND method='POST' AND user_id IS NULL")"
eq log 'an authenticated request was filed against its user' 't' \
  "$(psqlq "SELECT count(*) > 0 FROM hbh.request_log WHERE occurred_at >= '$RUN_START' AND username='a6_admin'")"
eq log 'every failure carries a code' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.request_log WHERE occurred_at >= '$RUN_START' AND status_code >= 400 AND error_code IS NULL")"
# SCOPED TO THE ROWS THIS SERVICE WROTE, not to a time window.
#
# It counted every row in hbh.request_log since the run began and found
# one - written by something else on this shared database, with
# route='/api/appointments' and no /v1 in it, so nothing this middleware
# could ever produce. The property held perfectly; the assertion was
# counting other people's rows.
#
# Third time this exact shape has bitten - the request identifier in a5,
# the day filter in a5, and now this. A window is not a scope: on a
# database somebody else is also writing to, only a key you own is.
eq log 'this service wrote no message text at all' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.request_log
            WHERE occurred_at >= '$RUN_START'
            AND   route LIKE '/api/v1/%'
            AND   (username LIKE 'a6\\_%' OR route = '/api/v1/enrolments')
            AND   error_message IS NOT NULL")"
eq log 'the health probe is not logged' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.request_log WHERE occurred_at >= '$RUN_START' AND path IN ('/healthz','/readyz')")"
eq log 'no query string was kept' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.request_log WHERE occurred_at >= '$RUN_START' AND path LIKE '%?%'")"

# =====================================================================
# STRUCTURE
#
# One invariant rather than one check per table: a DELETE grant that
# appears on the next table added is caught by the same line.
# =====================================================================
eq structure 'no table in the schema grants DELETE to the app role' '0' \
  "$(psqlq "SELECT count(*) FROM information_schema.role_table_grants WHERE grantee='hbh_app' AND table_schema='hbh' AND privilege_type='DELETE'")"
eq structure 'the request log is append-only' 't' \
  "$(psqlq "SELECT count(*) > 0 FROM pg_trigger WHERE tgrelid='hbh.request_log'::regclass AND tgname='trg_rlog_append_only' AND tgenabled='O'")"
eq structure 'the request log is not readable without OPS.VIEW' '0' \
  "$(psqlapp "SELECT count(*) FROM hbh.request_log")"
eq structure 'no anonymous read of a survey answer' '0' \
  "$(psqlapp "SELECT count(*) FROM hbh.nps_responses")"

# =====================================================================
# CLEANUP - a recorded check like any other
# =====================================================================
OUT="$(psqlf "$ROOT/tests/fixtures/a6_teardown.sql")"
RC=$?
if [ "$RC" != "0" ]; then chk cleanup 'fixture removed' 1 "$OUT"; else chk cleanup 'fixture removed' 0; fi
eq cleanup 'no application survived' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.enrolment_applications WHERE parent_mobile IN ('01500000062','01500000063','01500000064')")"
eq cleanup 'the seeded survey was left alone' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.nps_surveys WHERE code='PARENT_SESSION'")"

verdict 'API PHASE 6'
