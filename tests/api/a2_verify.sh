#!/usr/bin/env bash
# =====================================================================
# Hand By Hand (new) - API PHASE 2 acceptance suite
#
# Must print:  API PHASE 2 ACCEPTED
#
#   bash scripts/api.sh verify
#
# Phase 1 proved a parent cannot reach another family's child. This one
# is about what a parent may see of their OWN child, and the answer is
# not "everything".
#
# The centre's clinical record has a visibility ladder in it:
#
#   * a session note reaches a family only when it is marked PARENT,
#     is not a draft, and has been approved by somebody holding
#     NOTE.PUBLISH. Every note is born INTERNAL.
#   * a progress report reaches a family only when it is PUBLISHED.
#
# Both rungs are enforced by row level security, underneath the query.
# The `ladder` group below is the proof that they hold over HTTP - that
# a draft written about a parent's own child answers exactly like a
# document that was never written.
#
# The harness and the five rules it enforces are in tests/api/lib.sh.
# =====================================================================

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "=================== api phase 2 - the clinical record ==================="
echo "base: $API_BASE"
echo

# =====================================================================
# FIXTURE - asserted by name, before any test runs
# =====================================================================
OUT="$(psqlf "$ROOT/tests/fixtures/a2_teardown.sql")"
RC=$?
if [ "$RC" != "0" ]; then chk fixture 'previous fixture removed' 1 "$OUT"; else chk fixture 'previous fixture removed' 0; fi

OUT="$(psqlf "$ROOT/tests/fixtures/a2_fixture.sql")"
RC=$?
if [ "$RC" != "0" ]; then chk fixture 'fixture applied' 1 "$OUT"; else chk fixture 'fixture applied' 0; fi

RUN_START="$(psqlq "SELECT now()")"
CHILD_A="$(psqlq "SELECT child_id FROM hbh.children WHERE child_no = 'A2-A'")"
CHILD_B="$(psqlq "SELECT child_id FROM hbh.children WHERE child_no = 'A2-B'")"
REPORT_PUB="$(psqlq "SELECT report_id FROM hbh.progress_reports WHERE report_no = 'A2-RPT-PUB'")"
REPORT_DRAFT="$(psqlq "SELECT report_id FROM hbh.progress_reports WHERE report_no = 'A2-RPT-DRAFT'")"

# The boundary of the from/to window: 11:00 Cairo on the day of both
# appointments, expressed as a UTC instant. Computed by the database so
# the suite is not the place that decides what "11:00 in Cairo" means.
WINDOW_TO="$(psqlq "SELECT to_char(((date_trunc('week', now() AT TIME ZONE 'Africa/Cairo') + interval '7 days' + interval '11 hours') AT TIME ZONE 'Africa/Cairo') AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"')")"

ok_if fixture 'child A identifier known'        "$([ -n "$CHILD_A" ] && echo 0 || echo 1)" 'A2-A missing'
ok_if fixture 'child B identifier known'        "$([ -n "$CHILD_B" ] && echo 0 || echo 1)" 'A2-B missing'
ok_if fixture 'published report known'          "$([ -n "$REPORT_PUB" ] && echo 0 || echo 1)" 'A2-RPT-PUB missing'
ok_if fixture 'draft report known'              "$([ -n "$REPORT_DRAFT" ] && echo 0 || echo 1)" 'A2-RPT-DRAFT missing'
ok_if fixture 'window boundary computed'        "$([ -n "$WINDOW_TO" ] && echo 0 || echo 1)" 'no window boundary'
neq   fixture 'the two reports are different rows' "$REPORT_PUB" "$REPORT_DRAFT"

eq fixture 'service answers /healthz' '200' "$(req GET /healthz)"

TOKEN_A="$(login 01500000011)"
TOKEN_B="$(login 01500000012)"
ok_if fixture 'family A has a session' "$([ -n "$TOKEN_A" ] && echo 0 || echo 1)" 'no token for family A'
ok_if fixture 'family B has a session' "$([ -n "$TOKEN_B" ] && echo 0 || echo 1)" 'no token for family B'

# =====================================================================
# APPOINTMENTS
# =====================================================================
eq appt 'family A reads their appointments' '200' "$(req GET "/api/v1/children/$CHILD_A/appointments" '' "$TOKEN_A")"
eq appt 'both appointments are returned' '2' "$(jcount "$BODY" appointment_id)"
ok_if appt 'the service is named on the row' \
  "$(grep -q 'تخاطب — اختبار الـ API' "$BODY" && echo 0 || echo 1)" 'no service name in the payload'
ok_if appt 'the therapist is named on the row' \
  "$(grep -q 'أخصائية التخاطب' "$BODY" && echo 0 || echo 1)" 'no therapist name in the payload'
ok_if appt 'the room is named on the row' \
  "$(grep -q 'غرفة اختبار الـ API' "$BODY" && echo 0 || echo 1)" 'no room name in the payload'

# The internal booking note is deliberately not exposed - it has no
# approval step, unlike a session note.
eq appt 'the internal booking note is withheld' 'no' "$(jhas "$BODY" note_ar)"

eq appt 'the window narrows the list' '200' \
  "$(req GET "/api/v1/children/$CHILD_A/appointments?to=$WINDOW_TO" '' "$TOKEN_A")"
eq appt 'only the earlier appointment survives the window' '1' "$(jcount "$BODY" appointment_id)"

# A bare date is refused rather than guessed at: choosing which midnight
# it meant would be a business rule written in code.
eq appt 'a bare date is refused' '400' \
  "$(req GET "/api/v1/children/$CHILD_A/appointments?from=2026-09-03" '' "$TOKEN_A")"
eq appt 'the refusal names the code' 'VALIDATION' "$(jstr "$BODY" code)"
eq appt 'an out-of-range limit is refused' '400' \
  "$(req GET "/api/v1/children/$CHILD_A/appointments?limit=5000" '' "$TOKEN_A")"

# =====================================================================
# SESSIONS
# =====================================================================
eq session 'family A reads their sessions' '200' "$(req GET "/api/v1/children/$CHILD_A/sessions" '' "$TOKEN_A")"
eq session 'the completed session is returned' '1' "$(jcount "$BODY" session_id)"
eq session 'the session is closed' 'COMPLETED' "$(jstr "$BODY" status)"
ok_if session 'the session names its therapist' \
  "$(grep -q 'أخصائية التخاطب' "$BODY" && echo 0 || echo 1)" 'no therapist on the session'
eq session 'staff prose about an aborted session is withheld' 'no' "$(jhas "$BODY" abort_reason)"

# =====================================================================
# PLANS AND GOALS
# =====================================================================
eq plan 'family A reads the plan' '200' "$(req GET "/api/v1/children/$CHILD_A/plans" '' "$TOKEN_A")"
eq plan 'one plan is returned' '1' "$(jcount "$BODY" plan_id)"
eq plan 'both goals are attached' '2' "$(jcount "$BODY" goal_id)"

# Two measurements exist on the first goal, 41 then 62. A query that
# picked any measurement at all would pass with one; this is why the
# fixture writes two.
ok_if plan 'the latest measurement wins' \
  "$(grep -q '"latest_pct":62' "$BODY" && echo 0 || echo 1)" 'the newest measurement is not the one reported'
ok_if plan 'the superseded measurement is not reported' \
  "$(grep -q '"latest_pct":41' "$BODY" && echo 1 || echo 0)" 'an older measurement was reported as latest'
ok_if plan 'a measured goal counts its measurements' \
  "$(grep -q '"measurement_count":2' "$BODY" && echo 0 || echo 1)" 'measurement_count is wrong'
ok_if plan 'an unmeasured goal reports zero' \
  "$(grep -q '"measurement_count":0' "$BODY" && echo 0 || echo 1)" 'a goal with no measurements did not report 0'
ok_if plan 'an unmeasured goal reports a null day' \
  "$(grep -q '"latest_measured_on":null' "$BODY" && echo 0 || echo 1)" 'a missing measurement day was not null'

# =====================================================================
# THE LADDER
#
# This group is the phase.
# =====================================================================
eq ladder 'family A reads the notes' '200' "$(req GET "/api/v1/children/$CHILD_A/notes" '' "$TOKEN_A")"
eq ladder 'exactly one note is visible' '1' "$(jcount "$BODY" note_id)"
ok_if ladder 'the published note is the visible one' \
  "$(grep -q 'تحسّن ملحوظ في نطق السين' "$BODY" && echo 0 || echo 1)" 'the published note is missing'

# The one that must not be there. It is a note about this parent's own
# child, on the same session, written by the same therapist - and it is
# INTERNAL, which is the state every note is born in.
ok_if ladder 'the internal note never reaches the family' \
  "$(grep -q 'ملاحظة داخلية للفريق' "$BODY" && echo 1 || echo 0)" 'AN INTERNAL CLINICAL NOTE REACHED A GUARDIAN'

eq ladder 'family A reads the reports' '200' "$(req GET "/api/v1/children/$CHILD_A/reports" '' "$TOKEN_A")"
eq ladder 'exactly one report is visible' '1' "$(jcount "$BODY" report_id)"
eq ladder 'the visible report is the published one' 'A2-RPT-PUB' "$(jstr "$BODY" report_no)"
ok_if ladder 'the draft report is not listed' \
  "$(grep -q 'A2-RPT-DRAFT' "$BODY" && echo 1 || echo 0)" 'a draft report was listed to a guardian'

eq ladder 'the published report opens' '200' "$(req GET "/api/v1/reports/$REPORT_PUB" '' "$TOKEN_A")"
ok_if ladder 'it carries the frozen goal snapshot' \
  "$(grep -q 'goals_snapshot' "$BODY" && echo 0 || echo 1)" 'no goals_snapshot on the published report'
ok_if ladder 'it carries its summary' \
  "$(grep -q 'تقدّم ثابت خلال الفترة' "$BODY" && echo 0 || echo 1)" 'no summary on the published report'

# The strongest single check in this suite. The draft is about THIS
# parent's own child, and it is addressed directly by its identifier -
# the exact move the gate exists to stop. It must answer as though the
# report did not exist, because a parent learning that a report about
# their child exists before the clinician published it is itself a leak.
eq ladder 'a draft report about their own child is refused' '404' \
  "$(req GET "/api/v1/reports/$REPORT_DRAFT" '' "$TOKEN_A")"
eq ladder 'the refusal does not confirm existence' 'NOT_FOUND' "$(jstr "$BODY" code)"
eq ladder 'the refusal leaks no title' 'no' "$(jhas "$BODY" title_ar)"

# And the phase-1 gate still holds over the new routes.
eq ladder 'family B is refused family A published report' '404' \
  "$(req GET "/api/v1/reports/$REPORT_PUB" '' "$TOKEN_B")"

# =====================================================================
# THE GATE, EXTENDED
#
# Every nested route inherits the child gate. One route proving it is
# not enough: the helper is shared, but a route that forgot to use it
# would fail only its own check.
# =====================================================================
for path in appointments sessions plans reports notes; do
  eq gate "family B is refused child A $path" '404' \
    "$(req GET "/api/v1/children/$CHILD_A/$path" '' "$TOKEN_B")"
done
eq gate 'the nested refusal names the code' 'NOT_FOUND' "$(jstr "$BODY" code)"
eq gate 'an unauthenticated nested read is refused' '401' "$(req GET "/api/v1/children/$CHILD_A/notes")"

# =====================================================================
# DAYS ARE NOT INSTANTS
#
# A birth date and a report period are calendar days. Rendered as
# instants they arrive as 2020-03-15T00:00:00Z, and a client in Cairo
# reads that back as the 14th - the two-hour defect D-5 exists to
# remove, reintroduced at the edge of the system.
# =====================================================================
req GET "/api/v1/children/$CHILD_A" '' "$TOKEN_A" >/dev/null
eq date 'a birth date is a calendar day' '"birth_date":"2020-03-15"' "$(grep -o '"birth_date":"[^"]*"' "$BODY" | head -1)"

req GET "/api/v1/reports/$REPORT_PUB" '' "$TOKEN_A" >/dev/null
ok_if date 'a report period is a calendar day' \
  "$(grep -qE '"period_start":"[0-9]{4}-[0-9]{2}-[0-9]{2}"' "$BODY" && echo 0 || echo 1)" \
  'period_start is not a plain day'

# An instant stays an instant, and stays UTC.
req GET "/api/v1/children/$CHILD_A/appointments" '' "$TOKEN_A" >/dev/null
ok_if date 'an appointment time is a UTC instant' \
  "$(grep -qE '"starts_at":"[0-9-]{10}T[0-9:]{8}Z"' "$BODY" && echo 0 || echo 1)" \
  'starts_at is not a UTC instant'

# =====================================================================
# AUDIT
#
# Scoped to this run. The audit log is append-only, so an unscoped count
# passes once and fails for ever after.
# =====================================================================
audit_count() { psqlq "SELECT count(*) FROM hbh.audit_log WHERE changed_at >= '$RUN_START'::timestamptz AND $1"; }

ok_if audit 'reading the clinical record is recorded' \
  "$([ "$(audit_count "action = 'READ' AND detail = 'CHILD_APPOINTMENTS child_id=$CHILD_A'")" -ge 1 ] && echo 0 || echo 1)" \
  'no READ row for the appointments list'

ok_if audit 'reading a published report is recorded' \
  "$([ "$(audit_count "action = 'READ' AND detail LIKE 'REPORT report_id=$REPORT_PUB%'")" -ge 1 ] && echo 0 || echo 1)" \
  'no READ row for the report'

ok_if audit 'the refused draft is recorded' \
  "$([ "$(audit_count "action = 'DENY' AND detail = 'REPORT_NOT_VISIBLE report_id=$REPORT_DRAFT'")" -ge 1 ] && echo 0 || echo 1)" \
  'no DENY row for the draft report'

ok_if audit 'the refused nested read is recorded' \
  "$([ "$(audit_count "action = 'DENY' AND detail LIKE 'CHILD_NOT_VISIBLE child_id=$CHILD_A on=%'")" -ge 1 ] && echo 0 || echo 1)" \
  'no DENY row naming the route that was refused'

# =====================================================================
# TRANSPORT
# =====================================================================
eq transport 'a wrong method on a nested route is a JSON 405' '405' \
  "$(req POST "/api/v1/children/$CHILD_A/notes" '{}' "$TOKEN_A")"
eq transport 'the 405 names a code' 'METHOD_NOT_ALLOWED' "$(jstr "$BODY" code)"
eq transport 'a non-numeric child is not found' '404' \
  "$(req GET "/api/v1/children/abc/notes" '' "$TOKEN_A")"

# =====================================================================
# CLEANUP - a recorded check like any other
# =====================================================================
OUT="$(psqlf "$ROOT/tests/fixtures/a2_teardown.sql")"
RC=$?
if [ "$RC" != "0" ]; then
  chk cleanup 'fixture removed' 1 "$OUT"
else
  LEFT="$(psqlq "SELECT (SELECT count(*) FROM hbh.children WHERE child_no LIKE 'A2-%') + (SELECT count(*) FROM hbh.users WHERE username LIKE 'a2\\_%')")"
  eq cleanup 'nothing was left behind' '0' "$LEFT"
fi

# The teardown had to switch off two append-only triggers to remove the
# status history. A cleanup that left them off would have quietly
# disabled an integrity guarantee for every later run.
eq cleanup 'the append-only triggers are back on' '2' \
  "$(psqlq "SELECT count(*) FROM pg_trigger WHERE tgname IN ('trg_ash_append_only','trg_ssh_append_only') AND tgenabled = 'O'")"

verdict "API PHASE 2"
