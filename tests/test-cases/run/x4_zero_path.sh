#!/usr/bin/env bash
# X4 - THE PATH FROM ZERO.  HBH-015 · cases in tests/test-cases/15-zero-to-session.md
#
#   bash tests/test-cases/run/x4_zero_path.sh
#
# A stranger applies, reception triages and converts, the family is given
# portal access, THE PARENT SIGNS IN WITH THEIR OWN MOBILE, the child is
# put on a therapist's caseload, an appointment is booked, a session runs,
# a note is written and published - and the parent reads it.
#
# THE RULE: no owner-role write to any row of that path. Every one of
# them is made through the product's own route. The fixture creates the
# staff room and the catalogue and nothing else; the walk creates the
# family. `rule` at the bottom is that sentence made measurable - it
# reads the audit trail and fails if hbh_owner wrote any row of it.
#
# Reads as the owner are allowed and used: the application id is NOT in
# the submit response (by design - an anonymous caller must not be handed
# a handle to somebody's file), so it is read from the database by the
# mobile, the way a6 does it.
set -uo pipefail
cd "$(dirname "$0")/../../.."
. tests/api/lib.sh

MOBILE='01500000440'
CANON='+201500000440'

echo '=================== X4 - the path from zero ==================='
echo "base: $API_BASE"

# THE GROUND IS THREE THINGS, NOT TWO - and the third was learned here.
#
# Image id and migration ledger are the pair `scripts/api.sh verify`
# pins. They are not enough: this suite ran twice while another session
# was restarting the service, and both runs came back red - one with 000
# (the request never completed) and one with four failures no second run
# could reproduce. THE IMAGE ID WAS THE SAME AT BOTH ENDS, because a
# restart onto the same image moves nothing the pair can see.
#
# StartedAt does see it. A run that spans a restart is not a measurement
# of anything, and its red is worse than no number at all: it sends
# somebody looking for a defect in the product.
API_STARTED="$(docker inspect hbh-api --format '{{.State.StartedAt}}' 2>/dev/null)"
IMAGE="$(docker inspect hbh-api --format '{{.Image}}' 2>/dev/null | cut -c8-19)"
LEDGER="$(psqlq "SELECT count(*) || '|' || max(version) FROM hbh.schema_migrations")"
printf 'ground: image %s  ·  ledger %s  ·  service up since %s\n\n' \
       "${IMAGE:-?}" "${LEDGER:-?}" "${API_STARTED:-?}"

# --- the staff room ------------------------------------------------------
psqlf tests/fixtures/x4_teardown.sql >/dev/null 2>&1
FIXTURE_OUT="$(psqlf tests/fixtures/x4_fixture.sql 2>&1)"; FIXTURE_RC=$?
chk fixture 'the staff room was built' "$FIXTURE_RC" "$(printf '%s' "$FIXTURE_OUT" | tail -3)"
if [ "$FIXTURE_RC" != 0 ]; then verdict 'X4'; fi

RECEPTION="$(staff_login x4_reception 'x4-reception-pw-123456')"
ADMIN="$(staff_login x4_admin        'x4-admin-pw-123456')"
THERAPIST="$(staff_login x4_therapist 'x4-therapist-pw-123456')"
chk fixture 'reception signed in' "$([ -n "$RECEPTION" ] && echo 0 || echo 1)" 'no token'
chk fixture 'the administrator signed in' "$([ -n "$ADMIN" ] && echo 0 || echo 1)" 'no token'
chk fixture 'the therapist signed in' "$([ -n "$THERAPIST" ] && echo 0 || echo 1)" 'no token'
if [ -z "$RECEPTION" ] || [ -z "$ADMIN" ] || [ -z "$THERAPIST" ]; then verdict 'X4'; fi

TH="$(psqlq "SELECT t.therapist_id FROM hbh.therapists t JOIN hbh.users u ON u.user_id=t.user_id WHERE u.username='x4_therapist'")"
SVC="$(psqlq "SELECT service_id FROM hbh.services WHERE code='X4-SPEECH'")"
ROOM="$(psqlq "SELECT room_id FROM hbh.rooms WHERE code='X4-R1'")"

# =====================================================================
# Z-06..Z-08  the door a stranger walks through
# =====================================================================
APPLY="{\"center_code\":\"HBH\",\"parent_name_ar\":\"أسرة الطريق\",\"parent_mobile\":\"$MOBILE\",\"child_name_ar\":\"طفل الطريق\",\"child_birth_date\":\"2020-04-04\",\"child_gender\":\"F\"}"
eq door 'Z-06 a stranger with no token may apply' '201' "$(req POST /api/v1/enrolments "$APPLY")"
eq door 'Z-06 and is handed no identifier to anybody file' 'no' "$(jhas "$BODY" application_id)"

APP="$(psqlq "SELECT application_id FROM hbh.enrolment_applications WHERE parent_mobile = hbh.canonical_mobile('$MOBILE') ORDER BY application_id DESC LIMIT 1")"
chk door 'Z-07 the application reached the table' "$([ -n "$APP" ] && echo 0 || echo 1)" 'no application row for this run mobile'
eq door 'Z-07 reception sees it' '200' "$(req GET "/api/v1/enrolments/$APP" '' "$RECEPTION")"
eq door 'Z-07 and it is NEW' 'NEW' "$(jstr "$BODY" status)"
eq door 'Z-08 the stranger cannot read it back' '401' "$(req GET "/api/v1/enrolments/$APP")"

# The family cannot sign in yet, and the answer says which kind of "no"
# it is. This is the check that was missing when the portal half sat
# finished and unreachable for two weeks.
req POST /api/v1/auth/otp/request "{\"mobile\":\"$MOBILE\"}" >/dev/null
eq family 'Z-14 before access: the door names the pending application' 'ENROLMENT_PENDING' "$(jstr "$BODY" status)"
eq family 'Z-14 and issues no code' '' "$(jstr "$BODY" dev_code)"

# =====================================================================
# Z-09..Z-13  triage, one statement per transition
# =====================================================================
# Z-11a - WHILE THE ROW IS STILL 'NEW'.
#
# The refusal for a hand-typed ENROLLED has two shapes and the start
# state picks which: from NEW the transition itself is not in
# hbh.legal_enrolment_transition, so the state machine answers first
# (HB090 -> 409). From ASSESSMENT_BOOKED the transition IS legal - it is
# the move conversion makes - and what refuses is ck_enr_converted
# (23514 -> 400). Both are asked, in the only order that can ask them.
req PATCH "/api/v1/enrolments/$APP" '{"status":"ENROLLED"}' "$RECEPTION" >/dev/null
eq triage 'Z-11a from NEW the state machine refuses the jump' 'ILLEGAL_TRANSITION' "$(jstr "$BODY" code)"
eq triage 'Z-11a and the application is untouched' 'NEW' \
  "$(psqlq "SELECT status FROM hbh.enrolment_applications WHERE application_id=$APP")"

eq triage 'Z-09 reception records the call' '204' \
  "$(req PATCH "/api/v1/enrolments/$APP" '{"status":"CONTACTED","note_ar":"تم الاتصال"}' "$RECEPTION")"
# ASSESSMENT_BOOKED without a time is refused, and that is the handler
# being right: a booked assessment nobody can name a time for is how a
# family waits for a call that was never in anyone's diary.
ASSESS_AT="$(psqlq "SELECT to_char((now() + interval '3 days') AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"')")"
req PATCH "/api/v1/enrolments/$APP" '{"status":"ASSESSMENT_BOOKED"}' "$RECEPTION" >/dev/null
eq triage 'Z-10 booking an assessment with no time is refused' 'assessment_at' \
  "$(grep -o 'assessment_at' "$BODY" | head -1)"
eq triage 'Z-10 and books the assessment' '204' \
  "$(req PATCH "/api/v1/enrolments/$APP" "{\"status\":\"ASSESSMENT_BOOKED\",\"assessment_at\":\"$ASSESS_AT\"}" "$RECEPTION")"
eq triage 'Z-10 the row really moved' 'ASSESSMENT_BOOKED' \
  "$(psqlq "SELECT status FROM hbh.enrolment_applications WHERE application_id=$APP")"
# Z-11 MEASURED, AND THE CASE WAS REWRITTEN AROUND WHAT IT FOUND.
#
# It was written expecting ILLEGAL_TRANSITION, on the assumption that a
# jump to ENROLLED is not a legal move. It is legal:
# hbh.legal_enrolment_transition lists ASSESSMENT_BOOKED -> ENROLLED,
# because that IS the move conversion makes.
#
# What refuses the hand-typed one is ck_enr_converted -
#   (status = 'ENROLLED') = (converted_guardian_id IS NOT NULL
#                            AND converted_child_id IS NOT NULL)
# - a CHECK, so 23514, so 400 VALIDATION. The property is better than the
# one first written: ENROLLED is not a status anybody can type, it is
# what conversion leaves behind. A status screen that could set it would
# mark a family enrolled with no child and no guardian row anywhere.
req PATCH "/api/v1/enrolments/$APP" '{"status":"ENROLLED"}' "$RECEPTION" >/dev/null
eq triage 'Z-11b from ASSESSMENT_BOOKED the CHECK refuses it' 'VALIDATION' "$(jstr "$BODY" code)"
eq triage 'Z-11b and the application did not move' 'ASSESSMENT_BOOKED' \
  "$(psqlq "SELECT status FROM hbh.enrolment_applications WHERE application_id=$APP")"

eq triage 'Z-12 the application becomes a family' '201' \
  "$(req POST "/api/v1/enrolments/$APP/convert" '{"note_ar":"تم القبول"}' "$RECEPTION")"
CHILD="$(jnum "$BODY" child_id)"
GUARDIAN="$(jnum "$BODY" guardian_id)"
chk triage 'Z-12 the child id comes from the response' "$([ -n "$CHILD" ] && echo 0 || echo 1)" 'no child_id in the convert body'
chk triage 'Z-12 the guardian id comes from the response' "$([ -n "$GUARDIAN" ] && echo 0 || echo 1)" 'no guardian_id in the convert body'
eq triage 'Z-13 and the child carries a number from the series' 'yes' "$(jhas "$BODY" child_no)"

# =====================================================================
# Z-15..Z-20  the step that was cut: the family gets in
# =====================================================================
eq family 'Z-16 an unauthenticated caller may not open the account' '401' \
  "$(req POST "/api/v1/guardians/$GUARDIAN/portal-access" '{}')"
eq family 'Z-15 reception opens it' '200' \
  "$(req POST "/api/v1/guardians/$GUARDIAN/portal-access" '{}' "$RECEPTION")"
eq family 'Z-15 and the answer carries no password' 'no' "$(jhas "$BODY" password)"
eq family 'Z-15 a second click is not an error' '200' \
  "$(req POST "/api/v1/guardians/$GUARDIAN/portal-access" '{}' "$RECEPTION")"
eq family 'Z-15 and says it created nothing this time' 'false' "$(jbool "$BODY" created)"

PARENT="$(login "$MOBILE")"
chk family 'Z-17/Z-18 the parent signs in with their own mobile' \
   "$([ -n "$PARENT" ] && echo 0 || echo 1)" 'no session token for the family mobile'
eq family 'Z-18 and the session is real' '200' "$(req GET /api/v1/me '' "$PARENT")"
eq family 'Z-19 the parent sees exactly one child' '1' \
  "$(req GET /api/v1/children '' "$PARENT" >/dev/null; jcount "$BODY" child_id)"
eq family 'Z-19 and it is their own' 'yes' \
  "$(req GET /api/v1/children '' "$PARENT" >/dev/null; grep -q "\"child_id\"[[:space:]]*:[[:space:]]*$CHILD" "$BODY" && echo yes || echo no)"
eq family 'Z-20 another child id is not readable' '404' \
  "$(req GET '/api/v1/children/999999999' '' "$PARENT")"

# =====================================================================
# Z-21..Z-26  care begins
# =====================================================================
eq care 'Z-21 reception may NOT assign a therapist' '403' \
  "$(req POST "/api/v1/children/$CHILD/caseload" "{\"therapist_id\":$TH,\"service_id\":$SVC}" "$RECEPTION")"
eq care 'Z-21 the administrator may' '200' \
  "$(req POST "/api/v1/children/$CHILD/caseload" "{\"therapist_id\":$TH,\"service_id\":$SVC,\"is_primary\":true}" "$ADMIN")"
CASELOAD="$(jnum "$BODY" caseload_id)"
chk care 'Z-21 and returns the row' "$([ -n "$CASELOAD" ] && echo 0 || echo 1)" 'no caseload_id'
req POST "/api/v1/children/$CHILD/caseload" "{\"therapist_id\":$TH,\"service_id\":$SVC,\"is_primary\":true}" "$ADMIN" >/dev/null
eq care 'Z-22 a second assignment leaves ONE live row' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.caseload WHERE child_id=$CHILD AND active_flg")"

START="$(psqlq "SELECT to_char(((date_trunc('day', now() AT TIME ZONE 'Africa/Cairo') + interval '1 day' + interval '10 hours') AT TIME ZONE 'Africa/Cairo') AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"')")"
END="$(psqlq "SELECT to_char(((date_trunc('day', now() AT TIME ZONE 'Africa/Cairo') + interval '1 day' + interval '10 hours 45 minutes') AT TIME ZONE 'Africa/Cairo') AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"')")"
SLOT="{\"child_id\":$CHILD,\"therapist_id\":$TH,\"room_id\":$ROOM,\"service_id\":$SVC,\"starts_at\":\"$START\",\"ends_at\":\"$END\"}"

eq care 'Z-23 the slot validates' '200' "$(req POST /api/v1/appointments/validate "$SLOT" "$RECEPTION")"
eq care 'Z-23 and reports ok' 'true' "$(jbool "$BODY" ok)"
eq care 'Z-23 the appointment is booked' '201' "$(req POST /api/v1/appointments "$SLOT" "$RECEPTION")"
APPT="$(jnum "$BODY" appointment_id)"
chk care 'Z-23 the appointment id comes back' "$([ -n "$APPT" ] && echo 0 || echo 1)" 'no appointment_id'

eq care 'Z-24 confirmed' '204' "$(req PATCH "/api/v1/appointments/$APPT/status" '{"status":"CONFIRMED"}' "$RECEPTION")"
eq care 'Z-24 checked in'  '204' "$(req PATCH "/api/v1/appointments/$APPT/status" '{"status":"CHECKED_IN"}' "$RECEPTION")"
eq care 'Z-24 the therapist starts the session' '201' \
  "$(req POST "/api/v1/appointments/$APPT/session" '' "$THERAPIST")"
SESSION="$(jnum "$BODY" session_id)"
chk care 'Z-24 the session id comes back' "$([ -n "$SESSION" ] && echo 0 || echo 1)" 'no session_id'

eq care 'Z-25 the note is written' '201' \
  "$(req PUT "/api/v1/sessions/$SESSION/note" '{"body_ar":"جلسة أولى — الطريق من الصفر"}' "$THERAPIST")"
eq care 'Z-25 and is born internal' 'INTERNAL' "$(jstr "$BODY" visibility)"
NOTE="$(jnum "$BODY" note_id)"
eq closes 'Z-28 the family cannot see it yet' '0' \
  "$(req GET "/api/v1/children/$CHILD/notes" '' "$PARENT" >/dev/null; jcount "$BODY" note_id)"
eq care 'Z-25 the session closes' '204' \
  "$(req PATCH "/api/v1/sessions/$SESSION/close" '{"status":"COMPLETED"}' "$THERAPIST")"
eq care 'Z-25 the note is published' '204' "$(req POST "/api/v1/notes/$NOTE/publish" '' "$THERAPIST")"

# The plan names its service and its therapist, because the treatment
# plan table does: a plan with neither is a document nobody owns.
PLAN_START="$(psqlq "SELECT to_char(now() AT TIME ZONE 'Africa/Cairo', 'YYYY-MM-DD')")"
eq care 'Z-26 a plan is written for the child' '201' \
  "$(req POST /api/v1/plans "{\"child_id\":$CHILD,\"service_id\":$SVC,\"therapist_id\":$TH,\"title_ar\":\"خطة الطريق\",\"start_date\":\"$PLAN_START\"}" "$THERAPIST")"

# =====================================================================
# Z-27..Z-30  the loop closes at the family
# =====================================================================
eq closes 'Z-27 the parent reads the appointment' '1' \
  "$(req GET "/api/v1/children/$CHILD/appointments" '' "$PARENT" >/dev/null; jcount "$BODY" appointment_id)"
eq closes 'Z-28 and now reads the published note' '1' \
  "$(req GET "/api/v1/children/$CHILD/notes" '' "$PARENT" >/dev/null; jcount "$BODY" note_id)"
eq closes 'Z-29 and reads the plan' '1' \
  "$(req GET "/api/v1/children/$CHILD/plans" '' "$PARENT" >/dev/null; jcount "$BODY" plan_id)"
# Asks whether a value is there at all, not whether it looks like the one
# expected the day this was written: the numbers are stored '+20…' now.
eq closes 'Z-30 no mobile number rides along to the family' '0' \
  "$(req GET "/api/v1/children/$CHILD/notes" '' "$PARENT" >/dev/null; grep -o '"mobile"[[:space:]]*:[[:space:]]*"[^"]' "$BODY" | wc -l | tr -d ' ')"

# =====================================================================
# Z-31  THE RULE, MEASURED
#
# Every row of the family path, asked of the audit trail: who wrote it?
# If any of them names hbh_owner, then some part of this walk took the
# shortcut the card exists to forbid - and this check is the only thing
# that would notice.
# =====================================================================
# row_pk is TEXT in audit_log - the trail has to hold keys of every
# shape. Comparing it to a bare integer is not a mismatch Postgres
# forgives: the query ERRORS, psqlq swallows the error into an empty
# string, and `eq` then compares '0' with '' and fails for a reason that
# looks nothing like the one it is. The first run of this file did
# exactly that.
OWNER_ROWS="$(psqlq "
  SELECT count(*) FROM hbh.v_audit_trail
   WHERE changed_by = 'hbh_owner'
     AND action = 'INSERT'
     AND ( (table_name = 'enrolment_applications' AND row_pk = '$APP')
        OR (table_name = 'children'   AND row_pk = '$CHILD')
        OR (table_name = 'guardians'  AND row_pk = '$GUARDIAN')
        OR (table_name = 'caseload'   AND row_pk = '${CASELOAD:-0}')
        OR (table_name = 'appointments' AND row_pk = '${APPT:-0}')
        OR (table_name = 'therapy_sessions' AND row_pk = '${SESSION:-0}')
        OR (table_name = 'session_notes' AND row_pk = '${NOTE:-0}') )")"
eq rule 'Z-31 not one row of the path was written by the owner' '0' "$OWNER_ROWS"
# And the other half: the trail must have SEEN this path at all. Zero
# audited inserts would make the check above green while proving nothing
# - the same shape as a leak mask that stopped matching.
PATH_ROWS="$(psqlq "
  SELECT count(*) FROM hbh.v_audit_trail
   WHERE action = 'INSERT'
     AND ( (table_name = 'children'  AND row_pk = '$CHILD')
        OR (table_name = 'guardians' AND row_pk = '$GUARDIAN') )")"
# And it names the desk that did it, not a database role.
WROTE_BY="$(psqlq "
  SELECT DISTINCT changed_by FROM hbh.v_audit_trail
   WHERE action = 'INSERT' AND table_name = 'children' AND row_pk = '$CHILD'")"
eq rule 'Z-31 and the child was written by reception, by name' 'x4_reception' "$WROTE_BY"
chk rule 'Z-31 and the trail really recorded the path' \
   "$([ "${PATH_ROWS:-0}" -ge 2 ] && echo 0 || echo 1)" "audited inserts for child+guardian: ${PATH_ROWS:-0}"

# =====================================================================
# Z-32  cleanup is a recorded check
# =====================================================================
TEARDOWN_OUT="$(psqlf tests/fixtures/x4_teardown.sql 2>&1)"; TEARDOWN_RC=$?
chk cleanup 'Z-32 the teardown ran' "$TEARDOWN_RC" "$(printf '%s' "$TEARDOWN_OUT" | tail -3)"
eq cleanup 'Z-32 no child of this family is left' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.guardian_children gc JOIN hbh.guardians g ON g.guardian_id=gc.guardian_id WHERE g.mobile='$CANON'")"
eq cleanup 'Z-32 no account is left on the family mobile' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.users WHERE mobile='$CANON'")"
eq cleanup 'Z-32 no application is left' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.enrolment_applications WHERE parent_mobile='$CANON'")"
eq cleanup 'Z-32 the staff room is gone too' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.users WHERE username LIKE 'x4\_%'")"

# --- the ground did not move under the run -------------------------------
LEDGER2="$(psqlq "SELECT count(*) || '|' || max(version) FROM hbh.schema_migrations")"
IMAGE2="$(docker inspect hbh-api --format '{{.Image}}' 2>/dev/null | cut -c8-19)"
API_STARTED2="$(docker inspect hbh-api --format '{{.State.StartedAt}}' 2>/dev/null)"
if [ "$LEDGER" != "$LEDGER2" ] || [ "$IMAGE" != "$IMAGE2" ] || [ "$API_STARTED" != "$API_STARTED2" ]; then
  printf '\n  *** RUN VOID - the ground moved under this run. No verdict.\n'
  printf '      start: image %s · ledger %s · up since %s\n' "$IMAGE"  "$LEDGER"  "$API_STARTED"
  printf '      end:   image %s · ledger %s · up since %s\n' "$IMAGE2" "$LEDGER2" "$API_STARTED2"
  printf '      Re-run when the service is still. A red run that spans a\n'
  printf '      restart sends somebody hunting a defect that is not there.\n\n'
  exit 1
fi
printf '\nground: image %s  ·  ledger %s  ·  service up since %s\n' "$IMAGE2" "$LEDGER2" "$API_STARTED2"

verdict 'X4'
