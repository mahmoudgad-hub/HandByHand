#!/usr/bin/env bash
# =====================================================================
# Hand By Hand (new) - API PHASE 4 acceptance suite
#
# Must print:  API PHASE 4 ACCEPTED
#
#   bash scripts/api.sh verify 4
#
# The operations app: create, read, update and archive across the
# resources declared in api/internal/store/crud.go, plus the staff
# sign-in the whole thing needs.
#
# This batch exists because the owner decided Oracle stops and
# PostgreSQL becomes the source of truth (D-26). Until migration 0012
# the schema was READ-ONLY to the API by construction - 41 SELECT
# policies and not one write grant.
#
# THREE PROPERTIES ARE WORTH MORE THAN THE REST, and most of the checks
# below serve them:
#
#   1. THE PERMISSION DECIDES, NOT THE JOB TITLE. Reception can create
#      a child and cannot create a service. One account, two answers -
#      which a suite using only an administrator could never show.
#
#   2. NOTHING IS EVER HARD DELETED. There is no DELETE grant on any
#      table, the API's DELETE verb archives, and the row is still there
#      afterwards with a timestamp on it.
#
#   3. THE CLIENT CANNOT NAME THE CENTRE. center_id is derived from the
#      caller and is not on any allow list, so a body that tries to set
#      it is refused rather than honoured.
#
# The harness and the five rules it enforces are in tests/api/lib.sh.
# =====================================================================

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "=================== api phase 4 - the operations app ==================="
echo "base: $API_BASE"
echo

# =====================================================================
# FIXTURE - asserted by name, before any test runs
# =====================================================================
OUT="$(psqlf "$ROOT/tests/fixtures/a4_teardown.sql")"
RC=$?
if [ "$RC" != "0" ]; then chk fixture 'previous fixture removed' 1 "$OUT"; else chk fixture 'previous fixture removed' 0; fi

OUT="$(psqlf "$ROOT/tests/fixtures/a4_fixture.sql")"
RC=$?
if [ "$RC" != "0" ]; then chk fixture 'fixture applied' 1 "$OUT"; else chk fixture 'fixture applied' 0; fi

RUN_START="$(psqlq "SELECT now()")"
CHILD_A="$(psqlq "SELECT child_id FROM hbh.children WHERE child_no='A4-A'")"
ROOM="$(psqlq "SELECT room_id FROM hbh.rooms WHERE code='A4-ROOM'")"

eq fixture 'service answers /healthz' '200' "$(req GET /healthz)"
ok_if fixture 'the family child exists' "$([ -n "$CHILD_A" ] && echo 0 || echo 1)" 'A4-A missing'
ok_if fixture 'a room exists for the camera test' "$([ -n "$ROOM" ] && echo 0 || echo 1)" 'no room'

ADMIN="$(staff_login a4_admin a4-admin-pw-123456)"
RECEPTION="$(staff_login a4_reception a4-reception-pw-123456)"
PARENT="$(login 01500000032)"
ok_if fixture 'the administrator signed in' "$([ -n "$ADMIN" ] && echo 0 || echo 1)" 'no token for a4_admin'
ok_if fixture 'reception signed in'         "$([ -n "$RECEPTION" ] && echo 0 || echo 1)" 'no token for a4_reception'
ok_if fixture 'the guardian signed in'      "$([ -n "$PARENT" ] && echo 0 || echo 1)" 'no token for a4_parent'

# =====================================================================
# STAFF SIGN-IN
#
# Families prove a phone; staff prove a password. hbh.verify_password
# refuses to let the two paths cross.
# =====================================================================
eq auth 'a wrong password is refused' '401' \
  "$(req POST /api/v1/auth/staff/login '{"username":"a4_admin","password":"not-the-password"}')"
eq auth 'the refusal names the code' 'UNAUTHENTICATED' "$(jstr "$BODY" code)"

# An unknown user and a real user with the wrong password answer
# identically. Anything else tells an outsider which usernames exist.
eq auth 'an unknown user answers the same' '401' \
  "$(req POST /api/v1/auth/staff/login '{"username":"nobody_at_all","password":"not-the-password"}')"
eq auth 'and with the same code' 'UNAUTHENTICATED' "$(jstr "$BODY" code)"

# A guardian has no password, and being told so would confirm the
# account exists. Same answer again.
eq auth 'a guardian cannot use the staff door' '401' \
  "$(req POST /api/v1/auth/staff/login '{"username":"a4_parent","password":"anything"}')"
eq auth 'and is not told why' 'UNAUTHENTICATED' "$(jstr "$BODY" code)"

eq auth 'the staff token works on /me' '200' "$(req GET /api/v1/me '' "$ADMIN")"
eq auth 'and resolves to the right account' 'a4_admin' "$(jstr "$BODY" username)"

# =====================================================================
# THE CYCLE - create, read, update, archive, restore
# =====================================================================
eq crud 'a service can be created' '201' \
  "$(req POST /api/v1/services '{"code":"A4-SVC","name_ar":"خدمة الاختبار","kind_code":"SPEECH","default_duration_min":45}' "$ADMIN")"
SVC="$(jnum "$BODY" service_id)"
ok_if crud 'the new row came back' "$([ -n "$SVC" ] && echo 0 || echo 1)" 'no service_id in the response'

eq crud 'it appears in the list' '200' "$(req GET /api/v1/services '' "$ADMIN")"
ok_if crud 'by name' "$(grep -q 'خدمة الاختبار' "$BODY" && echo 0 || echo 1)" 'the new service is not listed'

eq crud 'it can be read on its own' '200' "$(req GET "/api/v1/services/$SVC" '' "$ADMIN")"
eq crud 'it can be updated' '200' \
  "$(req PATCH "/api/v1/services/$SVC" '{"name_ar":"خدمة معدّلة"}' "$ADMIN")"
ok_if crud 'the change stuck' "$(grep -q 'خدمة معدّلة' "$BODY" && echo 0 || echo 1)" 'the update did not apply'

eq crud 'it can be archived' '204' "$(req DELETE "/api/v1/services/$SVC" '' "$ADMIN")"
req GET /api/v1/services '' "$ADMIN" >/dev/null
ok_if crud 'an archived row leaves the default list' \
  "$(grep -q 'خدمة معدّلة' "$BODY" && echo 1 || echo 0)" 'an archived service is still listed'

# The manager can see what they archived. Without that, "delete" would
# be irreversible from the screen and the soft delete would have bought
# nothing - which is the whole reason migration 0013 exists.
req GET '/api/v1/services?archived=true' '' "$ADMIN" >/dev/null
ok_if crud 'but the manager can still see it' \
  "$(grep -q 'خدمة معدّلة' "$BODY" && echo 0 || echo 1)" 'the archived service is invisible to its own manager'

eq crud 'it can be restored' '204' "$(req POST "/api/v1/services/$SVC/restore" '' "$ADMIN")"
req GET /api/v1/services '' "$ADMIN" >/dev/null
ok_if crud 'and is back in the default list' \
  "$(grep -q 'خدمة معدّلة' "$BODY" && echo 0 || echo 1)" 'the restore did not work'

# =====================================================================
# NOTHING IS HARD DELETED
# =====================================================================
eq soft 'the archived row was never destroyed' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.services WHERE code='A4-SVC'")"

req DELETE "/api/v1/services/$SVC" '' "$ADMIN" >/dev/null
eq soft 'archiving sets the flag, not the axe' 'false' \
  "$(psqlq "SELECT active_flg::text FROM hbh.services WHERE code='A4-SVC'")"
ok_if soft 'and stamps the time' \
  "$([ -n "$(psqlq "SELECT deleted_at FROM hbh.services WHERE code='A4-SVC'")" ] && echo 0 || echo 1)" \
  'deleted_at was not stamped'
req POST "/api/v1/services/$SVC/restore" '' "$ADMIN" >/dev/null

# The guarantee underneath all of it: the role the API connects as
# cannot delete a row from any table in this schema, whatever the code
# above it says.
eq soft 'the API role holds no DELETE grant anywhere' '0' \
  "$(psqlq "SELECT count(*) FROM information_schema.role_table_grants WHERE grantee='hbh_app' AND table_schema='hbh' AND privilege_type='DELETE'")"

# =====================================================================
# THE PERMISSION DECIDES, NOT THE JOB TITLE
#
# One account, two answers. Reception is staff, is in the centre, and
# holds CHILD.CREATE but not CATALOG.MANAGE.
# =====================================================================
eq perm 'reception may register a child' '201' \
  "$(req POST /api/v1/children '{"child_no":"A4-B","full_name_ar":"طفل جديد","birth_date":"2021-04-04","gender":"M"}' "$RECEPTION")"
NEW_CHILD="$(jnum "$BODY" child_id)"
ok_if perm 'the new child came back with an identifier' \
  "$([ -n "$NEW_CHILD" ] && echo 0 || echo 1)" 'no child_id in the response'

# Registering and editing are separate rights with separate codes, and
# reception holds both. The edit also gives the audit group below an
# UPDATE to find - hbh.children is change-audited by a trigger, which is
# where a change record belongs (D-1).
eq perm 'reception may edit that child' '200' \
  "$(req PATCH "/api/v1/children/$NEW_CHILD" '{"full_name_ar":"طفل بعد التعديل"}' "$RECEPTION")"
ok_if perm 'the edit is readable back' \
  "$(grep -q 'طفل بعد التعديل' "$BODY" && echo 0 || echo 1)" 'the child edit did not apply'

# Archiving a child must have a VISIBLE effect.
#
# It did not. GET /children ignored active_flg and did not return it, so an
# archived child stayed in the list looking exactly like a live one - and the
# operations console reasonably concluded the archive had failed. Reported by
# the front-end session against a running build; these four checks are what
# would have caught it.
eq life 'the new child is listed while active' '200' "$(req GET /api/v1/children '' "$RECEPTION")"
ok_if life 'and carries its archive flag' \
  "$(grep -q '"active_flg"' "$BODY" && echo 0 || echo 1)" \
  'the list cannot tell an archived child from a live one'

eq life 'the child can be archived' '204' "$(req DELETE "/api/v1/children/$NEW_CHILD" '' "$RECEPTION")"
req GET /api/v1/children '' "$RECEPTION" >/dev/null
ok_if life 'and then LEAVES the list' \
  "$(grep -q "\"child_id\":$NEW_CHILD" "$BODY" && echo 1 || echo 0)" \
  'an archived child is still listed - archiving did nothing a screen can see'

req GET '/api/v1/children?archived=true' '' "$RECEPTION" >/dev/null
ok_if life 'but is still there when asked for' \
  "$(grep -q "\"child_id\":$NEW_CHILD" "$BODY" && echo 0 || echo 1)" \
  'the archived child cannot be found at all, so it cannot be restored'

eq life 'and can be restored' '204' "$(req POST "/api/v1/children/$NEW_CHILD/restore" '' "$RECEPTION")"

# Paging and search, so the console can show a page and say which one.
eq life 'the list reports a total' '200' "$(req GET '/api/v1/children?limit=1&page=1' '' "$RECEPTION")"
ok_if life 'and pages to one row' "$(grep -o '"child_id"' "$BODY" | wc -l | tr -d ' ' | grep -q '^1$' && echo 0 || echo 1)" \
  'limit=1 did not return one row'
ok_if life 'search finds by folded Arabic name' \
  "$(req GET '/api/v1/children?q=%D8%B7%D9%81%D9%84' '' "$RECEPTION" >/dev/null; grep -q '"child_id"' "$BODY" && echo 0 || echo 1)" \
  'a name search returned nothing'
eq life 'a nonsense search returns none' '0' \
  "$(req GET '/api/v1/children?q=zzzznotachild' '' "$RECEPTION" >/dev/null; jcount "$BODY" child_id)"

# A TYPED WILDCARD IS A CHARACTER, NOT A WILDCARD.
#
# The term has always been a bound parameter, so this was never injection.
# It was the quieter defect underneath: until the term was escaped, a
# receptionist who typed a single '%' was handed EVERY child in the centre,
# and a name holding '_' matched the wrong family. The two checks above
# cannot see either of those - a search that still works is exactly what a
# missing ESCAPE clause looks like.
#
# TWO THINGS ARE ASSERTED AROUND EACH COUNT, because a bare "zero rows"
# is the same answer as several failures that prove nothing:
#
#   - the unfiltered list is non-empty FIRST, or there was nothing for a
#     wildcard to over-match and the checks below pass on an empty table;
#   - each wildcard search answers 200, or a validation refusal would hand
#     back an error body with no child_id in it and read as a pass.
LISTED="$(req GET /api/v1/children '' "$RECEPTION" >/dev/null; jcount "$BODY" child_id)"
ok_if life 'the list has children for a wildcard to over-match' \
  "$([ "${LISTED:-0}" -gt 0 ] && echo 0 || echo 1)" \
  'the list is empty, so the wildcard checks below would pass on nothing'

eq life 'a search for % is accepted, not refused' '200' \
  "$(req GET '/api/v1/children?q=%25' '' "$RECEPTION")"
eq life 'and matches no child rather than all of them' '0' "$(jcount "$BODY" child_id)"

eq life 'a search for _ is accepted, not refused' '200' \
  "$(req GET '/api/v1/children?q=_' '' "$RECEPTION")"
eq life 'and matches no child either' '0' "$(jcount "$BODY" child_id)"

eq perm 'reception may NOT create a service' '403' \
  "$(req POST /api/v1/services '{"code":"A4-NOPE","name_ar":"x","kind_code":"SPEECH"}' "$RECEPTION")"
eq perm 'the refusal names the code' 'FORBIDDEN' "$(jstr "$BODY" code)"

# Reading is a different right from writing, and reception has it.
eq perm 'reception may still READ the catalogue' '200' "$(req GET /api/v1/services '' "$RECEPTION")"

# Cameras need CATALOG.MANAGE *and* LIVE.VIEW together. Reception has
# neither; the administrator has both.
eq perm 'reception may NOT create a camera' '403' \
  "$(req POST /api/v1/cameras "{\"room_id\":$ROOM,\"code\":\"A4-CAMX\",\"name_ar\":\"x\",\"gateway_path\":\"a4/x\"}" "$RECEPTION")"

eq perm 'the administrator may create a camera' '201' \
  "$(req POST /api/v1/cameras "{\"room_id\":$ROOM,\"code\":\"A4-CAM\",\"name_ar\":\"كاميرا الاختبار\",\"gateway_path\":\"a4-secret-path\"}" "$ADMIN")"

# Writable by an administrator, readable by nobody. CLAUDE.md: no camera
# link, address or credential anywhere a client can reach.
ok_if perm 'the camera path never comes back' \
  "$(grep -q 'a4-secret-path' "$BODY" && echo 1 || echo 0)" 'THE CAMERA GATEWAY PATH REACHED THE CLIENT'
eq perm 'nor is the field even present' 'no' "$(jhas "$BODY" gateway_path)"
req GET /api/v1/cameras '' "$ADMIN" >/dev/null
ok_if perm 'nor in the list' \
  "$(grep -q 'a4-secret-path' "$BODY" && echo 1 || echo 0)" 'the camera path leaked in a list'

# A guardian is not staff and holds none of it.
eq perm 'a guardian may not create a service' '403' \
  "$(req POST /api/v1/services '{"code":"A4-NOPE2","name_ar":"x","kind_code":"SPEECH"}' "$PARENT")"
eq perm 'a guardian may not register a child' '403' \
  "$(req POST /api/v1/children '{"child_no":"A4-X","full_name_ar":"x","birth_date":"2021-01-01","gender":"M"}' "$PARENT")"
eq perm 'a guardian may not archive a service' '404' \
  "$(req DELETE "/api/v1/services/$SVC" '' "$PARENT")"
eq perm 'an unauthenticated caller may not write' '401' \
  "$(req POST /api/v1/services '{"code":"A4-NOPE3","name_ar":"x","kind_code":"SPEECH"}')"

# =====================================================================
# THE CLIENT CANNOT NAME THE CENTRE
#
# center_id is derived from the caller (D-3) and is on no allow list, so
# a body that names it is refused rather than quietly ignored - which
# would be worse, because the caller would believe it had worked.
# =====================================================================
eq tenant 'a body naming center_id is refused' '400' \
  "$(req POST /api/v1/services '{"code":"A4-T","name_ar":"x","kind_code":"SPEECH","center_id":999}' "$ADMIN")"
eq tenant 'and the field is named back' 'center_id' "$(jstr "$BODY" field)"

eq tenant 'an update naming center_id is refused' '400' \
  "$(req PATCH "/api/v1/services/$SVC" '{"center_id":999}' "$ADMIN")"

# active_flg is not on any allow list either: archiving has its own
# path, and a client that could set the flag directly would bypass the
# timestamp that makes an archive auditable.
eq tenant 'a body naming active_flg is refused' '400' \
  "$(req PATCH "/api/v1/services/$SVC" '{"active_flg":false}' "$ADMIN")"

# And a status column that IS a state machine stays off the list.
eq tenant 'a plan status cannot be set directly' '400' \
  "$(req POST /api/v1/plans "{\"child_id\":$CHILD_A,\"title_ar\":\"خطة\",\"start_date\":\"2026-01-01\",\"status\":\"ACTIVE\"}" "$ADMIN")"

# =====================================================================
# WHAT THE SCHEMA WILL NOT TAKE
#
# A well-formed body the database refuses is the CALLER's mistake - 400,
# not 500 - and the answer names the kind of refusal without naming the
# constraint, which is a schema detail.
# =====================================================================
eq valid 'a duplicate code is refused' '400' \
  "$(req POST /api/v1/services '{"code":"A4-SVC","name_ar":"x","kind_code":"SPEECH"}' "$ADMIN")"
eq valid 'and is called a duplicate' 'DUPLICATE' "$(jstr "$BODY" constraint)"

eq valid 'a missing required column is refused' '400' \
  "$(req POST /api/v1/rooms '{"code":"A4-R"}' "$ADMIN")"
eq valid 'and is called required' 'REQUIRED' "$(jstr "$BODY" constraint)"

eq valid 'a date that is not a date is refused' '400' \
  "$(req POST /api/v1/children '{"child_no":"A4-D","full_name_ar":"x","birth_date":"the fourth","gender":"M"}' "$RECEPTION")"

eq valid 'an unknown field is refused' '400' \
  "$(req POST /api/v1/rooms '{"code":"A4-R2","name_ar":"x","nonsense":"1"}' "$ADMIN")"
eq valid 'and the field is named' 'nonsense' "$(jstr "$BODY" field)"

eq valid 'the constraint name is never disclosed' 'no' "$(jhas "$BODY" uq_services_code)"

# =====================================================================
# THE POLICY, NOT THE CODE
#
# Asserted as hbh_app - the role the API actually connects as - because
# a check run as the owner bypasses every policy and proves nothing.
# =====================================================================
eq policy 'reception is refused by the ENGINE, not by Go' 'f' \
  "$(psqlapp "SELECT set_config('hbh.user_id','a4_reception',false); SELECT hbh.has_permission('CATALOG.MANAGE')" | tail -1)"

# The output is captured FIRST and grepped afterwards, never piped.
#
# `set -o pipefail` is on, so `psqlapp | grep -q` reports PSQL's exit
# status - and psql exits non-zero exactly when the statement was
# refused, which is the case these two checks are looking for. Piping
# made the pipeline fail precisely when the test should have passed.
DIRECT="$(psqlapp "SELECT set_config('hbh.user_id','a4_reception',false); INSERT INTO hbh.services (center_id,code,name_ar,kind_code) VALUES (1,'A4-DIRECT','x','SPEECH')")"
ok_if policy 'a direct insert as reception is refused too' \
  "$(echo "$DIRECT" | grep -q 'row-level security' && echo 0 || echo 1)" \
  "the database allowed a write the API refuses - the gate is in the wrong layer: [$DIRECT]"

HARDDEL="$(psqlapp "SELECT set_config('hbh.user_id','a4_admin',false); DELETE FROM hbh.services WHERE code='A4-SVC'")"
ok_if policy 'a hard delete is refused by the ENGINE' \
  "$(echo "$HARDDEL" | grep -q 'permission denied' && echo 0 || echo 1)" \
  "the API role can hard-delete: [$HARDDEL]"

# =====================================================================
# AUDIT
# =====================================================================
audit_count() { psqlq "SELECT count(*) FROM hbh.audit_log WHERE changed_at >= '$RUN_START'::timestamptz AND $1"; }

ok_if audit 'the staff sign-in was recorded' \
  "$([ "$(audit_count "action='LOGIN' AND detail LIKE 'STAFF_LOGIN OK%'")" -ge 1 ] && echo 0 || echo 1)" \
  'no LOGIN row for the staff sign-in'

ok_if audit 'the wrong password was recorded' \
  "$([ "$(audit_count "action='DENY' AND detail LIKE 'STAFF_LOGIN%'")" -ge 1 ] && echo 0 || echo 1)" \
  'no DENY row for the refused password'

ok_if audit 'the refused write was recorded' \
  "$([ "$(audit_count "action='DENY' AND detail LIKE 'WRITE_REFUSED%'")" -ge 1 ] && echo 0 || echo 1)" \
  'no DENY row for the refused write'

# The change itself is recorded by the trigger inside the transaction
# that made it (D-1), not by the API - so a rolled back write takes its
# own record with it.
ok_if audit 'the creation was recorded by the trigger' \
  "$([ "$(audit_count "action='INSERT' AND table_name='services'")" -ge 1 ] && echo 0 || echo 1)" \
  'no INSERT row from hbh.trg_audit'

ok_if audit 'the archive was recorded as an update' \
  "$([ "$(audit_count "action='UPDATE' AND table_name='services'")" -ge 1 ] && echo 0 || echo 1)" \
  'no UPDATE row for the archive'

# The invariant, not the instance.
#
# Checking one table would have missed this: opening nine tables for
# writing in 0012 left every one of them with no change audit, because
# they had never needed one while they were read-only. An administrator
# could have repointed a camera and left nothing behind but the current
# value. Migration 0014 closed it; this check is what keeps it closed
# the next time a table is made writable.
#
# IT ASKS FOR THE PROPERTY, NOT FOR ONE FUNCTION'S NAME. It used to
# require hbh.trg_audit specifically, and went red on hbh.attachments -
# which IS audited, by a recorder of its own that strips the file
# content out of the record first, because a generic to_jsonb(NEW) would
# copy every uploaded file into the audit log. The table was right and
# the check was wrong: an invariant that names an implementation fails
# on the next legitimate one, and the pressure is then to weaken it.
eq audit 'every writable table has a change audit' '(none)' \
  "$(psqlq "SELECT coalesce(string_agg(g.table_name, ', '), '(none)')
            FROM  (SELECT DISTINCT table_name FROM information_schema.role_table_grants
                    WHERE grantee='hbh_app' AND table_schema='hbh'
                    AND   privilege_type IN ('INSERT','UPDATE')
                    AND   table_name <> 'audit_log') g
            WHERE NOT EXISTS (SELECT 1 FROM pg_trigger t
                              JOIN pg_class c ON c.oid = t.tgrelid
                              JOIN pg_namespace n ON n.oid = c.relnamespace
                              JOIN pg_proc p ON p.oid = t.tgfoid
                              WHERE n.nspname='hbh' AND c.relname = g.table_name
                              AND   NOT t.tgisinternal
                              AND   p.prosrc LIKE '%hbh.audit_log%')
            AND NOT EXISTS (SELECT 1 FROM hbh.convention_exemptions e
                            WHERE e.table_name = g.table_name
                            AND   e.rule_code = 'CHANGE_AUDIT')")"

# AND IT HONOURS hbh.convention_exemptions, which it did not until
# migration 0082.
#
# The schema has had an exemptions table since the conventions suite was
# written, holding AUDIT_COLUMNS and SOFT_DELETE decisions with a reason
# beside each one. This check ignored it - so the day a table legitimately
# needed to skip the rule, the only way to record that was to edit this
# file. CLAUDE.md says exactly why that is wrong: a rule whose exceptions
# live inside its own test is a rule each phase quietly edits.
#
# Nothing carries a CHANGE_AUDIT exemption today. The mechanism is here
# so that the first one is a written decision rather than a change to a
# test somebody makes at the end of a long day.
eq audit 'the exemption mechanism is reachable from here' 't' \
  "$(psqlq "SELECT count(*) >= 0 FROM hbh.convention_exemptions WHERE rule_code = 'CHANGE_AUDIT'")"

eq audit 'no camera path anywhere in the trail' '0' \
  "$(audit_count "detail LIKE '%a4-secret-path%'")"

# =====================================================================
# COLUMNS A FAMILY MAY NOT READ ON A ROW A FAMILY MAY READ
#
# Row level security filters ROWS. It does not filter COLUMNS, and these
# two endpoints are where that gap showed: p_therapists_select admits
# ANY authenticated user of the centre - correctly, since a parent
# choosing an appointment must see who the therapists are - and this
# service then returned the whole row, personal mobile number included.
#
# Found by reading the policy while reviewing somebody else's schema
# design, then confirmed against a running build before anything was
# changed. It had been live since batch 4.
#
# The mask is null rather than a missing key, so the object has the same
# shape for everybody: a field that vanishes for one caller makes a
# client guess which case it is in.
# =====================================================================
eq mask 'a guardian may list the therapists' '200' "$(req GET /api/v1/therapists '' "$PARENT")"
ok_if mask 'and sees who they are' \
  "$(grep -q '"full_name_ar"' "$BODY" && echo 0 || echo 1)" 'a guardian cannot see the therapists at all'
ok_if mask 'and NOT one mobile number among them' \
  "$(grep -qE '"mobile":"[0-9]' "$BODY" && echo 1 || echo 0)" \
  'a therapist mobile number reached a guardian'
ok_if mask 'nor the account behind the person' \
  "$(grep -qE '"user_id":[0-9]' "$BODY" && echo 1 || echo 0)" \
  'a therapist user_id reached a guardian'

eq mask 'the same list to staff' '200' "$(req GET /api/v1/therapists '' "$ADMIN")"
ok_if mask 'DOES carry the mobile' \
  "$(grep -qE '"mobile":"[0-9]' "$BODY" && echo 0 || echo 1)" \
  'the mask hid the number from the centre too, which is not the point'

# The same gap on the room list, and it had been documented and not
# enforced: domain.RoomRef has said since batch 2 that notes_ar is
# internal, while /api/v1/rooms returned it to anybody.
eq mask 'a guardian may list the rooms' '200' "$(req GET /api/v1/rooms '' "$PARENT")"
ok_if mask 'and not the internal note on them' \
  "$(grep -q 'a4-room-note' "$BODY" && echo 1 || echo 0)" \
  'a room note reached a guardian'
eq mask 'staff still read the note' '200' "$(req GET /api/v1/rooms '' "$ADMIN")"
ok_if mask 'as they must' \
  "$(grep -q 'a4-room-note' "$BODY" && echo 0 || echo 1)" 'the note is hidden from staff too'

# The primitive under the mask, asserted directly: it must FAIL CLOSED.
# A function returning NULL would make "NOT is_staff" unknown, and the
# mask would then leak on the one connection that matters - the
# unauthenticated one.
eq mask 'no identity is not staff' 'f' "$(psqlapp "SELECT hbh.current_user_is_staff()")"
eq mask 'and it is false, not null' '1' \
  "$(psqlapp "SELECT count(*) FROM (SELECT hbh.current_user_is_staff() AS a) x WHERE x.a IS NOT NULL")"

# =====================================================================
# TRANSPORT
# =====================================================================
eq transport 'an unknown resource is a JSON 404' '404' "$(req GET /api/v1/widgets '' "$ADMIN")"
eq transport 'a wrong method is a JSON 405' '405' "$(req PUT "/api/v1/services/$SVC" '{}' "$ADMIN")"
ALLOW="$(hdr Allow)"
ok_if transport 'Allow names every method the path takes' \
  "$(echo "$ALLOW" | grep -q 'PATCH' && echo "$ALLOW" | grep -q 'DELETE' && echo 0 || echo 1)" \
  "Allow was [$ALLOW]"
eq transport 'a non-numeric id is not found' '404' "$(req PATCH /api/v1/services/abc '{"name_ar":"x"}' "$ADMIN")"

# =====================================================================
# CLEANUP - a recorded check like any other
# =====================================================================
OUT="$(psqlf "$ROOT/tests/fixtures/a4_teardown.sql")"
RC=$?
if [ "$RC" != "0" ]; then
  chk cleanup 'fixture removed' 1 "$OUT"
else
  LEFT="$(psqlq "SELECT (SELECT count(*) FROM hbh.users WHERE username LIKE 'a4\\_%') + (SELECT count(*) FROM hbh.children WHERE child_no LIKE 'A4-%') + (SELECT count(*) FROM hbh.services WHERE code LIKE 'A4-%') + (SELECT count(*) FROM hbh.cameras WHERE code LIKE 'A4-%')")"
  eq cleanup 'nothing was left behind' '0' "$LEFT"
fi

verdict "API PHASE 4"
