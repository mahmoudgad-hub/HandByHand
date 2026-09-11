#!/usr/bin/env bash
# =====================================================================
# Hand By Hand (new) - API PHASE 5 acceptance suite
#
# Must print:  API PHASE 5 ACCEPTED
#
#   bash scripts/api.sh verify 5
#
# The centre-indexed reads, and the writes that make those screens do
# something.
#
# Everything before this batch was indexed by a CHILD, which is right
# for a parent: they enter through their child. A receptionist enters
# through a DAY, and building that from the child-scoped endpoints would
# mean one request per child and a merge in the browser - broken
# ordering, broken paging, and no knowledge of a child nobody asked for.
#
# The suite walks one appointment through its whole life over HTTP:
#
#   validate -> book -> confirm -> check in -> start -> note -> close
#
# and then the three ladders a centre crosses deliberately: publishing a
# report, issuing an invoice and taking a payment, deciding a family's
# request.
#
# THE FIXTURE DOES NOT CREATE AN APPOINTMENT. Booking is the thing under
# test, so the suite books it. A pre-booked row would let every later
# check pass while the booking path was broken.
#
# The harness and the five rules it enforces are in tests/api/lib.sh.
# =====================================================================

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "=================== api phase 5 - the centre's day ==================="
echo "base: $API_BASE"
echo

# =====================================================================
# FIXTURE - asserted by name, before any test runs
# =====================================================================
OUT="$(psqlf "$ROOT/tests/fixtures/a5_teardown.sql")"
RC=$?
if [ "$RC" != "0" ]; then chk fixture 'previous fixture removed' 1 "$OUT"; else chk fixture 'previous fixture removed' 0; fi

OUT="$(psqlf "$ROOT/tests/fixtures/a5_fixture.sql")"
RC=$?
if [ "$RC" != "0" ]; then chk fixture 'fixture applied' 1 "$OUT"; else chk fixture 'fixture applied' 0; fi

RUN_START="$(psqlq "SELECT now()")"
CHILD="$(psqlq "SELECT child_id FROM hbh.children WHERE child_no='A5-A'")"
TH="$(psqlq "SELECT t.therapist_id FROM hbh.therapists t JOIN hbh.users u ON u.user_id=t.user_id WHERE u.username='a5_therapist'")"
ROOM="$(psqlq "SELECT room_id FROM hbh.rooms WHERE code='A5-R1'")"
SVC="$(psqlq "SELECT service_id FROM hbh.services WHERE code='A5-SPEECH'")"
REPORT="$(psqlq "SELECT report_id FROM hbh.progress_reports WHERE report_no='A5-RPT'")"
INVOICE="$(psqlq "SELECT invoice_id FROM hbh.invoices WHERE invoice_no='A5-INV'")"
PKG="$(psqlq "SELECT package_id FROM hbh.service_packages WHERE code='A5-PKG'")"

# The slot, and the DAY it falls on in the centre's own time zone. The
# day matters: /appointments defaults to today, and the fixture books
# next Monday, so the suite must ask for that date explicitly.
SLOT1_START="$(psqlq "SELECT to_char(((date_trunc('week', now() AT TIME ZONE 'Africa/Cairo') + interval '7 days' + interval '10 hours') AT TIME ZONE 'Africa/Cairo') AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"')")"
SLOT1_END="$(psqlq "SELECT to_char(((date_trunc('week', now() AT TIME ZONE 'Africa/Cairo') + interval '7 days' + interval '10 hours 45 minutes') AT TIME ZONE 'Africa/Cairo') AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"')")"
SLOT2_START="$(psqlq "SELECT to_char(((date_trunc('week', now() AT TIME ZONE 'Africa/Cairo') + interval '7 days' + interval '13 hours') AT TIME ZONE 'Africa/Cairo') AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"')")"
SLOT2_END="$(psqlq "SELECT to_char(((date_trunc('week', now() AT TIME ZONE 'Africa/Cairo') + interval '7 days' + interval '13 hours 45 minutes') AT TIME ZONE 'Africa/Cairo') AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"')")"
DAY="$(psqlq "SELECT (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo') + interval '7 days')::date::text")"

for v in CHILD TH ROOM SVC REPORT INVOICE PKG SLOT1_START DAY; do
  eval "val=\$$v"
  ok_if fixture "$v is known" "$([ -n "$val" ] && echo 0 || echo 1)" "$v is empty"
done

eq fixture 'service answers /healthz' '200' "$(req GET /healthz)"

ADMIN="$(staff_login a5_admin a5-admin-pw-123456)"
THERAPIST="$(staff_login a5_therapist a5-therapist-pw-123456)"
COLLEAGUE="$(staff_login a5_colleague a5-colleague-pw-123456)"
PARENT="$(login 01500000052)"
ok_if fixture 'the administrator signed in' "$([ -n "$ADMIN" ] && echo 0 || echo 1)" 'no token for a5_admin'
ok_if fixture 'the therapist signed in'     "$([ -n "$THERAPIST" ] && echo 0 || echo 1)" 'no token for a5_therapist'
ok_if fixture 'the colleague signed in'     "$([ -n "$COLLEAGUE" ] && echo 0 || echo 1)" 'no token for a5_colleague'
ok_if fixture 'the guardian signed in'      "$([ -n "$PARENT" ] && echo 0 || echo 1)" 'no token for a5_parent'

SLOT="{\"child_id\":$CHILD,\"therapist_id\":$TH,\"room_id\":$ROOM,\"service_id\":$SVC,\"starts_at\":\"$SLOT1_START\",\"ends_at\":\"$SLOT1_END\"}"

# =====================================================================
# VALIDATE BEFORE BOOK
#
# The endpoint that decides whether the booking screen is usable. With
# it the receptionist learns the therapist is busy WHILE choosing;
# without it she fills the whole form and is refused at the end.
# =====================================================================
eq slot 'a free slot validates' '200' "$(req POST /api/v1/appointments/validate "$SLOT" "$ADMIN")"
eq slot 'and reports ok' 'true' "$(jbool "$BODY" ok)"
eq slot 'with a reason code' 'OK' "$(jstr "$BODY" reason)"

# A refusal is a 200 with ok:false, not an error status. The caller
# asked a question and got an answer - nothing failed.
BAD_SLOT="{\"child_id\":$CHILD,\"therapist_id\":$TH,\"room_id\":$ROOM,\"service_id\":$SVC,\"starts_at\":\"2020-01-01T09:00:00Z\",\"ends_at\":\"2020-01-01T09:45:00Z\"}"
eq slot 'a slot in the past is answered, not errored' '200' \
  "$(req POST /api/v1/appointments/validate "$BAD_SLOT" "$ADMIN")"
eq slot 'and reports not ok' 'false' "$(jbool "$BODY" ok)"
ok_if slot 'with a reason that is a code, not a sentence' \
  "$(grep -qE '"reason":"[A-Z_]+"' "$BODY" && echo 0 || echo 1)" \
  "reason was not a code: $(jstr "$BODY" reason)"

eq slot 'an inverted window is refused' '400' \
  "$(req POST /api/v1/appointments/validate "{\"child_id\":$CHILD,\"therapist_id\":$TH,\"room_id\":$ROOM,\"service_id\":$SVC,\"starts_at\":\"$SLOT1_END\",\"ends_at\":\"$SLOT1_START\"}" "$ADMIN")"

# The client cannot name the centre: it is derived from the caller.
eq slot 'a body naming center_id is refused' '400' \
  "$(req POST /api/v1/appointments/validate "{\"child_id\":$CHILD,\"therapist_id\":$TH,\"room_id\":$ROOM,\"service_id\":$SVC,\"starts_at\":\"$SLOT1_START\",\"ends_at\":\"$SLOT1_END\",\"center_id\":999}" "$ADMIN")"

# =====================================================================
# BOOK
# =====================================================================
eq book 'the slot can be booked' '201' "$(req POST /api/v1/appointments "$SLOT" "$ADMIN")"
APPT="$(jnum "$BODY" appointment_id)"
ok_if book 'and returns its identifier' "$([ -n "$APPT" ] && echo 0 || echo 1)" 'no appointment_id'

# The same slot again. Three exclusion constraints - therapist, room,
# child - are what actually stop a double booking, so two receptionists
# racing end with one appointment and one refusal (D-13).
eq book 'the same slot no longer validates' '200' \
  "$(req POST /api/v1/appointments/validate "$SLOT" "$ADMIN")"
eq book 'and says so' 'false' "$(jbool "$BODY" ok)"

eq book 'booking it twice is refused' '409' "$(req POST /api/v1/appointments "$SLOT" "$ADMIN")"
ok_if book 'and names a conflict, not a fault' \
  "$(grep -qE '"code":"(SLOT_TAKEN|SLOT_UNAVAILABLE|REFUSED)"' "$BODY" && echo 0 || echo 1)" \
  "got $(jstr "$BODY" code)"

# A FREE slot, not the taken one - otherwise a 409 for "slot gone"
# would masquerade as a permission refusal and prove nothing.
#
# This gap was real: before migration 0016 hbh.book_appointment checked
# the SLOT and never the CALLER, so a guardian booked straight into the
# diary and got 201. A family asks and the centre decides, which is why
# parent_requests exists at all.
SLOT2="{\"child_id\":$CHILD,\"therapist_id\":$TH,\"room_id\":$ROOM,\"service_id\":$SVC,\"starts_at\":\"$SLOT2_START\",\"ends_at\":\"$SLOT2_END\"}"
eq book 'the second slot is genuinely free' 'true' \
  "$(req POST /api/v1/appointments/validate "$SLOT2" "$ADMIN" >/dev/null; jbool "$BODY" ok)"
eq book 'a guardian may not book even a free slot' '403' \
  "$(req POST /api/v1/appointments "$SLOT2" "$PARENT")"
eq book 'and is refused for the right reason' 'FORBIDDEN' "$(jstr "$BODY" code)"

# =====================================================================
# THE DAY VIEW
#
# The reason this batch exists: one call returns a day, with names on
# every row.
# =====================================================================
# Scoped to THIS fixture's therapist. The day view is centre-wide by
# design - that is the point of it - so counting every row on the day
# would count whatever else the centre has booked, and the check would
# pass or fail depending on what another suite left behind.
eq day 'the day can be read' '200' "$(req GET "/api/v1/appointments?date=$DAY&therapist_id=$TH" '' "$ADMIN")"
eq day 'it holds the booking' '1' "$(jcount "$BODY" appointment_id)"
eq day 'and reports a total' '1' "$(jnum "$BODY" total)"
ok_if day 'and it is the one just booked' \
  "$(grep -q "\"appointment_id\":$APPT" "$BODY" && echo 0 || echo 1)" \
  'the day view does not contain the appointment the suite created'

ok_if day 'the child is NAMED on the row' \
  "$(grep -q 'طفل الدفعة الخامسة' "$BODY" && echo 0 || echo 1)" \
  'the row carries no child name - the screen would need a call per row'
ok_if day 'the therapist is named' \
  "$(grep -q 'أخصائية التخاطب' "$BODY" && echo 0 || echo 1)" 'no therapist name'
ok_if day 'the room is named' \
  "$(grep -q 'غرفة الدفعة الخامسة' "$BODY" && echo 0 || echo 1)" 'no room name'
ok_if day 'the service is named' \
  "$(grep -q 'تخاطب — الدفعة الخامسة' "$BODY" && echo 0 || echo 1)" 'no service name'

ok_if day 'times are UTC instants' \
  "$(grep -qE '"starts_at":"[0-9-]{10}T[0-9:]{8}Z"' "$BODY" && echo 0 || echo 1)" \
  'starts_at is not a UTC instant'

# A different day must not contain it. Without this the date filter
# could be ignored entirely and every check above would still pass.
ok_if day 'another day does not contain it' \
  "$(req GET "/api/v1/appointments?date=2020-01-06" '' "$ADMIN" >/dev/null; grep -q "\"appointment_id\":$APPT" "$BODY" && echo 1 || echo 0)" \
  "appointment $APPT appeared on a day it is not on"

eq day 'a therapist filter that matches keeps it' '1' \
  "$(req GET "/api/v1/appointments?date=$DAY&therapist_id=$TH" '' "$ADMIN" >/dev/null; jcount "$BODY" appointment_id)"
eq day 'a room filter that does not match drops it' '0' \
  "$(req GET "/api/v1/appointments?date=$DAY&room_id=999999" '' "$ADMIN" >/dev/null; jcount "$BODY" appointment_id)"
# SCOPED TO THIS SUITE'S OWN APPOINTMENT, not to a centre-wide count.
#
# It asked for zero COMPLETED appointments on this day and got one -
# belonging to a PA- fixture from another session, on the same Monday.
# The filter was working perfectly; the assertion was counting rows this
# suite does not own.
#
# The same lesson as the request identifier, in the place it was not
# applied: a centre-indexed list contains other people's rows BY DESIGN,
# so the question has to be "is MINE excluded", never "how many are
# there".
ok_if day 'a status filter that does not match drops it' \
  "$(req GET "/api/v1/appointments?date=$DAY&status=COMPLETED" '' "$ADMIN" >/dev/null; grep -q "\"appointment_id\":$APPT" "$BODY" && echo 1 || echo 0)" \
  "the booked appointment $APPT appeared under status=COMPLETED"

eq day 'a malformed date is refused' '400' "$(req GET '/api/v1/appointments?date=6-1-2020' '' "$ADMIN")"
eq day 'a malformed instant is refused' '400' "$(req GET '/api/v1/appointments?from=today' '' "$ADMIN")"
eq day 'a bad page is refused' '400' "$(req GET '/api/v1/appointments?page=0' '' "$ADMIN")"

# A guardian asking the same endpoint sees their own child's day - the
# policy decides, not a second endpoint.
eq day 'a guardian may read the same endpoint' '200' "$(req GET "/api/v1/appointments?date=$DAY" '' "$PARENT")"
eq day 'and sees their own child' '1' "$(jcount "$BODY" appointment_id)"

# =====================================================================
# THE SESSION
# =====================================================================
eq sess 'a session cannot start before check-in' '409' \
  "$(req POST "/api/v1/appointments/$APPT/session" '' "$THERAPIST")"
eq sess 'and says why' 'NOT_CHECKED_IN' "$(jstr "$BODY" code)"

eq sess 'the appointment can be confirmed' '204' \
  "$(req PATCH "/api/v1/appointments/$APPT/status" '{"status":"CONFIRMED"}' "$ADMIN")"
eq sess 'and checked in' '204' \
  "$(req PATCH "/api/v1/appointments/$APPT/status" '{"status":"CHECKED_IN"}' "$ADMIN")"

# A status to ITSELF is a no-op, not a refusal: trg_appointment_status
# only validates when the status actually changes. That makes PATCH
# idempotent, which is what a screen that may retry needs.
eq sess 'setting the same status again is a no-op' '204' \
  "$(req PATCH "/api/v1/appointments/$APPT/status" '{"status":"CHECKED_IN"}' "$ADMIN")"

# A genuinely illegal move IS refused - by the machine, not by the API.
eq sess 'going backwards is refused' '409' \
  "$(req PATCH "/api/v1/appointments/$APPT/status" '{"status":"BOOKED"}' "$ADMIN")"
eq sess 'and names the reason' 'ILLEGAL_TRANSITION' "$(jstr "$BODY" code)"

eq sess 'the session starts' '201' "$(req POST "/api/v1/appointments/$APPT/session" '' "$THERAPIST")"
SESSION="$(jnum "$BODY" session_id)"
ok_if sess 'and returns its identifier' "$([ -n "$SESSION" ] && echo 0 || echo 1)" 'no session_id'

eq sess 'a second session on one appointment is refused' '409' \
  "$(req POST "/api/v1/appointments/$APPT/session" '' "$THERAPIST")"
eq sess 'and names the reason' 'SESSION_EXISTS' "$(jstr "$BODY" code)"

# No date: the session started NOW, not on the appointment day, so
# today is the correct question and the default is the right answer.
#
# FILTERED BY THERAPIST, and that is not decoration. This database is
# shared with the other suites and with two other sessions working on
# it, so "every session in the centre today" is a number this suite does
# not control - and a check that counts it passes until somebody else's
# fixture runs a session on the same day. The therapist belongs to this
# fixture, so the count is this suite's own.
eq sess 'the day of sessions can be read' '200' "$(req GET "/api/v1/sessions?therapist_id=$TH" '' "$ADMIN")"
eq sess 'it holds the running session' '1' "$(jcount "$BODY" session_id)"
ok_if sess 'and it is the one just started' \
  "$(grep -q "\"session_id\":$SESSION" "$BODY" && echo 0 || echo 1)" "session $SESSION is not in the day"
eq sess 'which is in progress' 'IN_PROGRESS' "$(jstr "$BODY" status)"
ok_if sess 'and names the child' \
  "$(grep -q 'طفل الدفعة الخامسة' "$BODY" && echo 0 || echo 1)" 'no child name on the session row'
ok_if sess 'and carries started_at for the counter' \
  "$(grep -q '"started_at"' "$BODY" && echo 0 || echo 1)" 'no started_at'

# A note is born INTERNAL. Reaching the family is a separate act.
eq note 'the therapist can write a note' '201' \
  "$(req PUT "/api/v1/sessions/$SESSION/note" '{"body_ar":"ملاحظة الجلسة من الاختبار"}' "$THERAPIST")"
eq note 'and it is born internal' 'INTERNAL' "$(jstr "$BODY" visibility)"
eq note 'the family cannot see it yet' '0' \
  "$(req GET "/api/v1/children/$CHILD/notes" '' "$PARENT" >/dev/null; jcount "$BODY" note_id)"

eq note 'an empty note is refused' '400' \
  "$(req PUT "/api/v1/sessions/$SESSION/note" '{"body_ar":"  "}' "$THERAPIST")"
eq note 'a guardian may not write one' '403' \
  "$(req PUT "/api/v1/sessions/$SESSION/note" '{"body_ar":"x"}' "$PARENT")"

# TWO REFUSALS THAT USED TO BE ONE.
#
# can_edit_session asks two questions and returned one false, so a
# therapist who HELD the right and was writing on a colleague's session
# got the same answer as somebody with no right at all - and the screen
# had to tell a person with the permission that their permission did not
# allow it. Migration 0030 split them.
#
# The ORDER inside the function is what makes the second message safe to
# be specific about: the permission is asked FIRST, so a stranger never
# learns whether the session exists or whose it is. Reverse it and this
# refusal becomes a way to probe the diary.
eq note 'the centre manager may not write a clinical note' '403' \
  "$(req PUT "/api/v1/sessions/$SESSION/note" '{"body_ar":"ملاحظة من الإدارة"}' "$ADMIN")"
eq note 'and is told plainly that the right is missing' 'FORBIDDEN' "$(jstr "$BODY" code)"

eq note 'a colleague with the right may not write on this session' '403' \
  "$(req PUT "/api/v1/sessions/$SESSION/note" '{"body_ar":"ملاحظة من زميلة"}' "$COLLEAGUE")"
eq note 'and is told WHY, which is a different reason' 'NOT_YOUR_SESSION' "$(jstr "$BODY" code)"
eq note 'the colleague really does hold the right' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.users u
            JOIN hbh.user_roles ur ON ur.user_id = u.user_id
            JOIN hbh.role_permissions rp ON rp.role_id = ur.role_id
            JOIN hbh.permissions p ON p.permission_id = rp.permission_id
            WHERE u.username='a5_colleague' AND p.code='SESSION.NOTES.EDIT'")"
eq note 'and neither refusal wrote anything' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.session_notes WHERE session_id=$SESSION")"

eq sess 'the session closes' '204' \
  "$(req PATCH "/api/v1/sessions/$SESSION/close" '{"status":"COMPLETED"}' "$THERAPIST")"
# Closing an already-closed session is a no-op for the same reason: the
# status is not changing, so the machine is never consulted.
eq sess 'closing it again is a no-op' '204' \
  "$(req PATCH "/api/v1/sessions/$SESSION/close" '{"status":"COMPLETED"}' "$THERAPIST")"
eq sess 'and it is still completed' 'COMPLETED' \
  "$(psqlq "SELECT status FROM hbh.therapy_sessions WHERE session_id=$SESSION")"

# =====================================================================
# THE THREE LADDERS
# =====================================================================
eq ladder 'staff see the draft report' '200' "$(req GET /api/v1/reports '' "$ADMIN")"
ok_if ladder 'including its draft status' \
  "$(grep -q '"status":"DRAFT"' "$BODY" && echo 0 || echo 1)" 'the draft is not listed to staff'
ok_if ladder 'and the child is named on it' \
  "$(grep -q 'طفل الدفعة الخامسة' "$BODY" && echo 0 || echo 1)" 'no child name on the report row'

# The same endpoint, a guardian: the policy withholds the draft.
eq ladder 'a guardian sees no draft report' '0' \
  "$(req GET /api/v1/reports '' "$PARENT" >/dev/null; jcount "$BODY" report_id)"

eq ladder 'the report publishes' '204' "$(req POST "/api/v1/reports/$REPORT/publish" '' "$ADMIN")"
eq ladder 'publishing twice is refused' '409' "$(req POST "/api/v1/reports/$REPORT/publish" '' "$ADMIN")"
eq ladder 'and now the family sees it' '1' \
  "$(req GET "/api/v1/children/$CHILD/reports" '' "$PARENT" >/dev/null; jcount "$BODY" report_id)"

eq bill 'staff see the draft invoice' '200' "$(req GET /api/v1/invoices '' "$ADMIN")"
ok_if bill 'amounts are exact decimal strings' \
  "$(grep -qE '"total_amt":"[0-9]+\.[0-9]{2}"' "$BODY" && echo 0 || echo 1)" \
  'an amount came back as a number, not an exact decimal string'
eq bill 'a guardian sees no draft invoice' '0' \
  "$(req GET "/api/v1/children/$CHILD/invoices" '' "$PARENT" >/dev/null; jcount "$BODY" invoice_id)"

eq bill 'the invoice issues' '204' "$(req POST "/api/v1/invoices/$INVOICE/issue" '' "$ADMIN")"
eq bill 'and now the family sees it' '1' \
  "$(req GET "/api/v1/children/$CHILD/invoices" '' "$PARENT" >/dev/null; jcount "$BODY" invoice_id)"

eq bill 'a payment can be taken' '201' \
  "$(req POST "/api/v1/invoices/$INVOICE/payments" '{"amount":"400.00","method_code":"CASH"}' "$ADMIN")"
# The triggers refuse a payment beyond what is outstanding. Not a check
# written in Go.
eq bill 'overpayment is refused' '409' \
  "$(req POST "/api/v1/invoices/$INVOICE/payments" '{"amount":"999999.00","method_code":"CASH"}' "$ADMIN")"
eq bill 'a payment with no amount is refused' '400' \
  "$(req POST "/api/v1/invoices/$INVOICE/payments" '{"method_code":"CASH"}' "$ADMIN")"
eq bill 'a guardian may not take money' '403' \
  "$(req POST "/api/v1/invoices/$INVOICE/payments" '{"amount":"1.00","method_code":"CASH"}' "$PARENT")"

eq bill 'a package can be sold' '201' \
  "$(req POST "/api/v1/children/$CHILD/packages" "{\"package_id\":$PKG}" "$ADMIN")"
# 409 and not 403, and the reason is worth stating: hbh.sell_package
# raises HB052, which the schema uses BOTH for "needs BILLING.MANAGE"
# and for "this invoice can no longer change". The two cannot be told
# apart from the code, so the mapping picks the one that does not
# assert a permission problem that may not exist. The refusal is real
# either way - the guardian did not sell anything.
eq bill 'a guardian may not sell one' '409' \
  "$(req POST "/api/v1/children/$CHILD/packages" "{\"package_id\":$PKG}" "$PARENT")"

# =====================================================================
# WHO IS RESPONSIBLE FOR THIS CHILD
#
# The printed identity card carries two emergency numbers on its back,
# and a number taken from an unordered read is a number that may belong
# to another family - on a card nobody holding it can check.
#
# So the order is TOTAL: primary, then oldest link, then identifier.
# Migration 0032 made the first term decisive on its own; the other two
# cover what that index does not, which is several NON-primary guardians.
# =====================================================================
eq guardians 'the centre reads a child''s guardians' '200' \
  "$(req GET "/api/v1/children/$CHILD/guardians" '' "$ADMIN")"
eq guardians 'and there is one on file' '1' "$(jnum "$BODY" total)"
ok_if guardians 'named, with a number to ring' \
  "$(grep -q '"mobile"' "$BODY" && echo 0 || echo 1)" 'no mobile on the guardian row'
ok_if guardians 'and the relationship' \
  "$(grep -q '"relationship_code"' "$BODY" && echo 0 || echo 1)" 'no relationship on the guardian row'
ok_if guardians 'and whether they have an account' \
  "$(grep -q '"has_account"' "$BODY" && echo 0 || echo 1)" 'no has_account flag'
ok_if guardians 'the first one is the primary' \
  "$(grep -q '"is_primary":true' "$BODY" && echo 0 || echo 1)" 'the primary guardian is not marked'

# The gate is the child, as everywhere: no separate ownership check in
# the handler, and no way to walk the identifiers.
eq guardians 'a child nobody may see is 404' '404' \
  "$(req GET "/api/v1/children/99999999/guardians" '' "$ADMIN")"
eq guardians 'and it needs a token at all' '401' \
  "$(req GET "/api/v1/children/$CHILD/guardians")"

# One primary per child, and the database says so rather than the order
# happening to look right.
eq guardians 'exactly one primary link exists' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.guardian_children WHERE child_id=$CHILD AND is_primary_flg AND active_flg")"

# =====================================================================
# AUTHORING AN INVOICE
#
# The billing screen had two actions - issue and take payment - and no
# way to reach either, because both work on an invoice that ALREADY
# exists and nothing in the schema created one. The console session
# found it by having to INSERT by hand to finish testing.
#
# Everything the caller does NOT send is the point of these checks: the
# number, the currency and the tax rate come from the centre, and the
# totals are computed. A caller who could send them could bill a family
# in a currency the centre does not use, at a rate nobody approved.
# =====================================================================
eq author 'an invoice can be created' '201' \
  "$(req POST /api/v1/invoices "{\"child_id\":$CHILD}" "$ADMIN")"
NEWINV="$(jnum "$BODY" invoice_id)"
ok_if author 'and it has an identifier' "$([ -n "$NEWINV" ] && echo 0 || echo 1)" 'no invoice_id'

eq author 'it is born a draft' '200' "$(req GET "/api/v1/invoices/$NEWINV" '' "$ADMIN")"
eq author 'in DRAFT'            'DRAFT' "$(jstr "$BODY" status)"
eq author 'with nothing owed yet' '0.00' "$(jstr "$BODY" total_amt)"
ok_if author 'numbered from the centre series' \
  "$(grep -q '"invoice_no":"INV-' "$BODY" && echo 0 || echo 1)" 'the invoice number is not from hbh.next_number'
eq author 'and in the centre currency' 'EGP' "$(jstr "$BODY" currency_code)"
eq author 'the due date was filled in from the parameter' 't' \
  "$(psqlq "SELECT due_date IS NOT NULL FROM hbh.invoices WHERE invoice_id=$NEWINV")"
eq author 'and a guardian was attached to it' 't' \
  "$(psqlq "SELECT guardian_id IS NOT NULL FROM hbh.invoices WHERE invoice_id=$NEWINV")"

eq author 'a line can be added' '201' \
  "$(req POST "/api/v1/invoices/$NEWINV/lines" '{"description_ar":"جلستا تخاطب","qty":"2","unit_amt":"150.00"}' "$ADMIN")"
LINE="$(jnum "$BODY" line_id)"
# The total is COMPUTED and never sent. The suite writes no amount
# except the unit price, and the arithmetic is the database's (D-17).
eq author 'and the total is computed, not sent' '300.00' \
  "$(req GET "/api/v1/invoices/$NEWINV" '' "$ADMIN" >/dev/null; jstr "$BODY" total_amt)"

eq author 'a line with no description is refused' '400' \
  "$(req POST "/api/v1/invoices/$NEWINV/lines" '{"qty":"1","unit_amt":"10.00"}' "$ADMIN")"
eq author 'a guardian may not create an invoice' '409' \
  "$(req POST /api/v1/invoices "{\"child_id\":$CHILD}" "$PARENT")"
eq author 'a guardian may not add a line' '409' \
  "$(req POST "/api/v1/invoices/$NEWINV/lines" '{"description_ar":"x","qty":"1","unit_amt":"1.00"}' "$PARENT")"
eq author 'an invoice for a child nobody may see is refused' '403' \
  "$(req POST /api/v1/invoices '{"child_id":99999999}' "$ADMIN")"

eq author 'a line can be removed' '204' \
  "$(req DELETE "/api/v1/invoices/$NEWINV/lines/$LINE" '' "$ADMIN")"
eq author 'and the total follows it down' '0.00' \
  "$(req GET "/api/v1/invoices/$NEWINV" '' "$ADMIN" >/dev/null; jstr "$BODY" total_amt)"
eq author 'the line is archived, not deleted' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.invoice_lines WHERE line_id=$LINE AND NOT active_flg")"

# Once a family has been given a number to pay, the number stops moving.
eq author 'a line before issuing is fine' '201' \
  "$(req POST "/api/v1/invoices/$NEWINV/lines" '{"description_ar":"جلسة","qty":"1","unit_amt":"100.00"}' "$ADMIN")"
LINE2="$(jnum "$BODY" line_id)"
eq author 'the invoice issues' '204' "$(req POST "/api/v1/invoices/$NEWINV/issue" '' "$ADMIN")"
eq author 'and a line can no longer be added' '409' \
  "$(req POST "/api/v1/invoices/$NEWINV/lines" '{"description_ar":"متأخرة","qty":"1","unit_amt":"50.00"}' "$ADMIN")"
eq author 'and says the transition is illegal' 'ILLEGAL_TRANSITION' "$(jstr "$BODY" code)"
eq author 'nor removed' '409' \
  "$(req DELETE "/api/v1/invoices/$NEWINV/lines/$LINE2" '' "$ADMIN")"
eq author 'the amount stood still' '100.00' \
  "$(psqlq "SELECT total_amt FROM hbh.invoices WHERE invoice_id=$NEWINV")"

# =====================================================================
# WHAT A THERAPIST OFFERS
#
# The link that decides whether a booking is possible at all. There was
# no endpoint that wrote it, so a centre could create therapists,
# services, rooms and children through this API and then never book -
# validate_slot answers THERAPIST_SERVICE_MISMATCH and nothing the
# console could do would change it.
#
# The proof is the round trip: remove the link and watch a slot that
# validated stop validating.
# =====================================================================
SLOT2="{\"child_id\":$CHILD,\"therapist_id\":$TH,\"room_id\":$ROOM,\"service_id\":$SVC,\"starts_at\":\"$SLOT2_START\",\"ends_at\":\"$SLOT2_END\"}"

eq offers 'the services are listed' '200' "$(req GET "/api/v1/therapists/$TH/services" '' "$ADMIN")"
ok_if offers 'and the fixture link is in them' \
  "$(grep -q "\"service_id\":$SVC" "$BODY" && echo 0 || echo 1)" 'the therapist offers nothing'

eq offers 'the free slot validates while the link exists' 'true' \
  "$(req POST /api/v1/appointments/validate "$SLOT2" "$ADMIN" >/dev/null; jbool "$BODY" ok)"

eq offers 'the link can be removed' '204' \
  "$(req DELETE "/api/v1/therapists/$TH/services/$SVC" '' "$ADMIN")"
eq offers 'it is archived, not deleted' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.therapist_services WHERE therapist_id=$TH AND service_id=$SVC AND NOT active_flg")"
eq offers 'and now the same slot is refused' 'false' \
  "$(req POST /api/v1/appointments/validate "$SLOT2" "$ADMIN" >/dev/null; jbool "$BODY" ok)"
eq offers 'for the reason that matters' 'THERAPIST_SERVICE_MISMATCH' "$(jstr "$BODY" reason)"

eq offers 'the link can be given back' '204' \
  "$(req POST "/api/v1/therapists/$TH/services" "{\"service_id\":$SVC}" "$ADMIN")"
eq offers 'the archived row was reused, not duplicated' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.therapist_services WHERE therapist_id=$TH AND service_id=$SVC")"
eq offers 'and the slot validates again' 'true' \
  "$(req POST /api/v1/appointments/validate "$SLOT2" "$ADMIN" >/dev/null; jbool "$BODY" ok)"

eq offers 'a guardian may not change what a therapist offers' '403' \
  "$(req POST "/api/v1/therapists/$TH/services" "{\"service_id\":$SVC}" "$PARENT")"
eq offers 'a therapist nobody may see is not found' '404' \
  "$(req POST "/api/v1/therapists/99999999/services" "{\"service_id\":$SVC}" "$ADMIN")"

# =====================================================================
# THE OTHER SIDE OF THE PORTAL'S DOOR
# =====================================================================
eq request 'the family submits a request' '201' \
  "$(req POST "/api/v1/children/$CHILD/requests" '{"kind_code":"CALLBACK","body_ar":"أرجو الاتصال."}' "$PARENT")"

# THE IDENTIFIER COMES FROM THE DATABASE, NOT FROM THE LIST.
#
# It used to be read out of the centre-wide response with jnum, which
# returns the LAST match on the line - so the moment another suite left
# a request in this centre, this one picked up somebody else's row and
# decided it. The list is centre-indexed by design; a suite that reads
# an id out of it is trusting a number it does not own.
REQ="$(psqlq "SELECT pr.request_id FROM hbh.parent_requests pr
              JOIN hbh.children c ON c.child_id = pr.child_id WHERE c.child_no='A5-A'")"
ok_if request 'the request id is known' "$([ -n "$REQ" ] && echo 0 || echo 1)" 'the request was not written'
eq request 'exactly one, for this child' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.parent_requests pr
            JOIN hbh.children c ON c.child_id = pr.child_id WHERE c.child_no='A5-A'")"

eq request 'reception sees it' '200' "$(req GET /api/v1/requests '' "$ADMIN")"
ok_if request 'and it is in the day' \
  "$(grep -q "\"request_id\":$REQ" "$BODY" && echo 0 || echo 1)" "request $REQ is not in the list"
eq request 'still awaiting a decision' 'NEW' \
  "$(psqlq "SELECT status FROM hbh.parent_requests WHERE request_id=$REQ")"
ok_if request 'with the child named' \
  "$(grep -q 'طفل الدفعة الخامسة' "$BODY" && echo 0 || echo 1)" 'no child name on the request row'
ok_if request 'and the guardian named' \
  "$(grep -q 'وليّ الأمر' "$BODY" && echo 0 || echo 1)" 'no guardian name on the request row'

ok_if request 'a kind filter that does not match drops it' \
  "$(req GET '/api/v1/requests?kind=RESCHEDULE' '' "$ADMIN" >/dev/null; grep -q "\"request_id\":$REQ" "$BODY" && echo 1 || echo 0)" \
  'a CALLBACK request survived a RESCHEDULE filter'

APPT_STATUS_BEFORE="$(psqlq "SELECT status FROM hbh.appointments WHERE appointment_id=$APPT")"
eq request 'reception decides it' '204' \
  "$(req PATCH "/api/v1/requests/$REQ" '{"status":"ACCEPTED","note_ar":"تم الاتصال."}' "$ADMIN")"
# Deciding again is a no-op, not a refusal: the status is already
# ACCEPTED and trg_request_status only checks a transition that moves.
eq request 'deciding again is a no-op' '204' \
  "$(req PATCH "/api/v1/requests/$REQ" '{"status":"ACCEPTED"}' "$ADMIN")"
eq request 'and the decision stands' 'ACCEPTED' \
  "$(psqlq "SELECT status FROM hbh.parent_requests WHERE request_id=$REQ")"
eq request 'a guardian may not decide' '403' \
  "$(req PATCH "/api/v1/requests/$REQ" '{"status":"REJECTED"}' "$PARENT")"

# Accepting "please move Tuesday" moves nothing by itself. The
# appointment is changed separately and deliberately - a decision that
# silently rescheduled would make the request the diary's source of
# truth, which it is not.
# Accepting "please move Tuesday" moves nothing by itself. The
# appointment is changed separately and deliberately - a decision that
# silently rescheduled would make the request the diary's source of
# truth, which it is not. Compared against what the status was BEFORE
# the decision, not against a hard-coded value.
eq request 'accepting a request moved no appointment' "$APPT_STATUS_BEFORE" \
  "$(psqlq "SELECT status FROM hbh.appointments WHERE appointment_id=$APPT")"

# =====================================================================
# AUDIT
# =====================================================================
audit_count() { psqlq "SELECT count(*) FROM hbh.audit_log WHERE changed_at >= '$RUN_START'::timestamptz AND $1"; }

ok_if audit 'reading the day is recorded' \
  "$([ "$(audit_count "action='READ' AND detail='CENTRE_APPOINTMENTS'")" -ge 1 ] && echo 0 || echo 1)" \
  'no READ row for the day view'
ok_if audit 'the booking was recorded by the trigger' \
  "$([ "$(audit_count "action='INSERT' AND table_name='appointments'")" -ge 1 ] && echo 0 || echo 1)" \
  'no INSERT row from hbh.trg_audit'
ok_if audit 'a refused write was recorded' \
  "$([ "$(audit_count "action='DENY'")" -ge 1 ] && echo 0 || echo 1)" \
  'no DENY row at all'

# =====================================================================
# THE INVARIANT, NOT THE INSTANCE
#
# A trigger runs as the CALLER, so everything it touches is reached with
# the caller's rights. While hbh_app could not write, no trigger ever
# fired as hbh_app and this was invisible. Opening writes surfaced it
# three times in a row - the two history triggers (0017) and the payment
# recalculation (0021) - each found only when a suite hit it.
#
# This check finds the fourth one before it is written: every trigger on
# a table hbh_app may write must either be SECURITY DEFINER, or call
# only functions hbh_app may execute and touch only tables it may write.
# =====================================================================
eq trigger 'no trigger on a writable table calls a function the app role cannot execute' '(none)' \
  "$(psqlq "
    SELECT coalesce(string_agg(DISTINCT c.relname || '.' || p.proname, ', '), '(none)')
    FROM   pg_trigger t
    JOIN   pg_class c     ON c.oid = t.tgrelid
    JOIN   pg_namespace n ON n.oid = c.relnamespace
    JOIN   pg_proc p      ON p.oid = t.tgfoid
    WHERE  n.nspname = 'hbh'
    AND    NOT t.tgisinternal
    AND    NOT p.prosecdef
    AND    c.relname IN (SELECT DISTINCT table_name FROM information_schema.role_table_grants
                          WHERE grantee = 'hbh_app' AND table_schema = 'hbh'
                          AND   privilege_type IN ('INSERT','UPDATE'))
    AND    EXISTS (
             SELECT 1 FROM pg_proc callee
             JOIN   pg_namespace cn ON cn.oid = callee.pronamespace
             WHERE  cn.nspname = 'hbh'
             AND    p.prosrc LIKE '%hbh.' || callee.proname || '(%'
             AND    NOT has_function_privilege('hbh_app', callee.oid, 'EXECUTE'))")"

# =====================================================================
# TRANSPORT
# =====================================================================
eq transport 'an unauthenticated day read is refused' '401' "$(req GET /api/v1/appointments)"
eq transport 'a wrong method is a JSON 405' '405' "$(req DELETE /api/v1/appointments '' "$ADMIN")"
eq transport 'a non-numeric appointment is not found' '404' \
  "$(req PATCH /api/v1/appointments/abc/status '{"status":"CONFIRMED"}' "$ADMIN")"

# =====================================================================
# CLEANUP - a recorded check like any other
# =====================================================================
OUT="$(psqlf "$ROOT/tests/fixtures/a5_teardown.sql")"
RC=$?
if [ "$RC" != "0" ]; then
  chk cleanup 'fixture removed' 1 "$OUT"
else
  LEFT="$(psqlq "SELECT (SELECT count(*) FROM hbh.users WHERE username LIKE 'a5\\_%') + (SELECT count(*) FROM hbh.children WHERE child_no LIKE 'A5-%') + (SELECT count(*) FROM hbh.services WHERE code LIKE 'A5-%')")"
  eq cleanup 'nothing was left behind' '0' "$LEFT"
fi

eq cleanup 'the append-only guards are back on' '3' \
  "$(psqlq "SELECT count(*) FROM pg_trigger WHERE tgname IN ('trg_ash_append_only','trg_ssh_append_only','trg_led_append_only') AND tgenabled='O'")"

verdict "API PHASE 5"
