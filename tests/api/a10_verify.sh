#!/usr/bin/env bash
# =====================================================================
# Hand By Hand (new) - API PHASE 10 acceptance suite
#
# Must print:  API PHASE 10 ACCEPTED
#
#   bash scripts/api.sh verify 10
#
# The last eight routes no suite mentioned.
#
# HOW THEY WERE MISSED, because it matters more than the count. The
# first inventory matched a route by its FIRST path segment, so
# /children/{id}/photo looked covered because some suite mentions the
# word "children". Ten routes came back. Matching the whole path pattern
# returned eighteen. The lesson is the one this project keeps paying
# for: searching for a word does not prove a path is exercised, and it
# was true of my own audit two hours after I said it about somebody
# else's.
#
# WHAT THIS SUITE HOLDS DOWN:
#
#   1. A CHILD ID IN A PATH IS NOT AUTHORISATION. /children/{id}/profile
#      is the portal's own read. The check that matters is a REAL family
#      of the SAME centre asking for the other family's child - a
#      stranger is refused by the centre rule long before this one.
#
#   2. THE PHOTOGRAPH IS AUTHENTICATED, SO NO <img src> CAN REACH IT.
#      That single property is why a child's photograph is an attachment
#      and not a link, and why hbh.children has no photo_url column any
#      more. It is asserted as 401, on a photograph that really exists.
#
#   3. AND ITS GATE IS PROVED FROM BOTH SIDES - refused with no consent,
#      ACCEPTED once consent is recorded. A refusal on its own proves a
#      gate is shut, not that it opens: this product shipped a consent
#      check asking for a type the schema has never had, refusing every
#      photograph for a fortnight while its first assertion stayed green.
#
#   4. AN ADMINISTRATIVE RIGHT IS NOT A CLINICAL ONE. a10_therapist is
#      staff in this centre and is refused every USER.MANAGE and
#      STAFF.MANAGE route - so none of those refusals can be passing
#      merely because guardians are refused.
#
#   5. CHANGING A PASSWORD NEEDS THE OLD ONE, and issuing somebody
#      else's setup code is an administrative act. Both are asserted by
#      the CODE they answer with, not just by status.
#
# WHY THE LAST_ADMIN GUARD IS TESTED THROUGH THE DATABASE AND NOT OVER
# HTTP: see the `roles` group. It is the one check here that would do
# real damage if it ever failed.
#
# The harness and the five rules it enforces are in tests/api/lib.sh.
# =====================================================================

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "============== api phase 10 - the last uncovered routes =============="
echo "base: $API_BASE"
echo

# The two files this suite uploads, written here rather than committed.
# A binary in the repository is a binary nobody reviews, and these carry
# no information - the JPEG is a header and an end marker, which is all
# the mime sniffing looks at, and the PDF is four bytes for the same
# reason. Written with printf: a heredoc would mangle the escapes.
printf '\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xff\xd9' > "$TMP/a10.jpg"
printf '%%PDF-1.4\n1 0 obj\n<<>>\nendobj\ntrailer\n<<>>\n%%%%EOF\n'                    > "$TMP/a10.pdf"

# =====================================================================
# FIXTURE - asserted by name, before any test runs
# =====================================================================
OUT="$(psqlf "$ROOT/tests/fixtures/a10_teardown.sql")"
RC=$?
if [ "$RC" != "0" ]; then chk fixture 'previous fixture removed' 1 "$OUT"; else chk fixture 'previous fixture removed' 0; fi

OUT="$(psqlf "$ROOT/tests/fixtures/a10_fixture.sql")"
RC=$?
if [ "$RC" != "0" ]; then chk fixture 'fixture applied' 1 "$OUT"; else chk fixture 'fixture applied' 0; fi

eq fixture 'service answers /healthz' '200' "$(req GET /healthz)"

CHILD_A="$(psqlq "SELECT child_id FROM hbh.children WHERE child_no='A10-A'")"
CHILD_B="$(psqlq "SELECT child_id FROM hbh.children WHERE child_no='A10-B'")"
USER_ADMIN="$(psqlq "SELECT user_id FROM hbh.users WHERE username='a10_admin'")"
USER_TH="$(psqlq "SELECT user_id FROM hbh.users WHERE username='a10_therapist'")"
GUARDIAN_1="$(psqlq "SELECT g.guardian_id FROM hbh.guardians g JOIN hbh.users u ON u.user_id=g.user_id WHERE u.username='a10_parent1'")"
for v in CHILD_A CHILD_B USER_ADMIN USER_TH GUARDIAN_1; do
  eval "val=\$$v"
  ok_if fixture "$v is known" "$([ -n "$val" ] && echo 0 || echo 1)" "$v is empty"
done
neq fixture 'the two children are different rows' "$CHILD_A" "$CHILD_B"

ADMIN="$(staff_login a10_admin a10-admin-pw-123456)"
THERAPIST="$(staff_login a10_therapist a10-therapist-pw-123456)"
PARENT1="$(login 01500000292)"
PARENT2="$(login 01500000293)"
for pair in "ADMIN a10_admin" "THERAPIST a10_therapist" "PARENT1 a10_parent1" "PARENT2 a10_parent2"; do
  set -- $pair
  eval "tok=\$$1"
  ok_if fixture "$2 signed in" "$([ -n "$tok" ] && echo 0 || echo 1)" "no token for $2"
  req GET /api/v1/me '' "$tok" >/dev/null
  eq fixture "the $2 token really is $2" "$2" "$(jstr "$BODY" username)"
done

# =====================================================================
# THE CHILD'S PROFILE
# =====================================================================
eq profile 'an anonymous caller reads nothing' '401' \
  "$(req GET "/api/v1/children/$CHILD_A/profile")"
eq profile 'a family reads its own child' '200' \
  "$(req GET "/api/v1/children/$CHILD_A/profile" '' "$PARENT1")"
eq profile 'and it is the right child' 'A10-A' "$(jstr "$BODY" child_no)"

# THE CHECK THIS GROUP EXISTS FOR. a10_parent2 is a real family of this
# centre, so the centre rule cannot be what refuses them.
eq profile 'the OTHER family is refused' '404' \
  "$(req GET "/api/v1/children/$CHILD_B/profile" '' "$PARENT1")"
# 404 and not 403: a refusal that says "exists, but not yours" confirms
# the child exists to somebody guessing identifiers.
eq profile 'and the refusal confirms nothing' 'NOT_FOUND' "$(jstr "$BODY" code)"
eq profile 'the other family reads their own' '200' \
  "$(req GET "/api/v1/children/$CHILD_B/profile" '' "$PARENT2")"
eq profile 'clinical staff read either' '200' \
  "$(req GET "/api/v1/children/$CHILD_A/profile" '' "$THERAPIST")"
eq profile 'a child id must be a number' '404' \
  "$(req GET "/api/v1/children/abc/profile" '' "$ADMIN")"

# =====================================================================
# THE CHILD'S PHOTOGRAPH
# =====================================================================
eq photo 'there is no photograph yet' '404' \
  "$(req GET "/api/v1/children/$CHILD_A/photo" '' "$ADMIN")"

# The gate, shut. The fixture records no consent precisely so this is a
# state the product produced rather than one the fixture arranged.
eq photo 'uploading with no consent is refused' '409' \
  "$(reqfile POST "/api/v1/children/$CHILD_A/photo" "$TMP/a10.jpg" 'image/jpeg' "$ADMIN")"
eq photo 'and says what is missing' 'PHOTO_CONSENT_MISSING' "$(jstr "$BODY" code)"
eq photo 'nothing was stored' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.attachments WHERE child_id=$CHILD_A AND active_flg")"

# The gate, opened. Without this half the check above proves only that
# the gate is shut - which is exactly how a gate with no key stays green.
eq photo 'the family records its consent' '201' \
  "$(req POST "/api/v1/guardians/$GUARDIAN_1/consent" "{\"consent_type\":\"PHOTO_USE\",\"child_id\":$CHILD_A,\"text_version\":\"v1\"}" "$ADMIN")"
eq photo 'and now the photograph is accepted' '201' \
  "$(reqfile POST "/api/v1/children/$CHILD_A/photo" "$TMP/a10.jpg" 'image/jpeg' "$ADMIN")"
eq photo 'one photograph on file' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.attachments WHERE child_id=$CHILD_A AND active_flg")"

# THE LOAD-BEARING ONE. A photograph now exists, and an anonymous caller
# still gets nothing. This is why the photograph is an attachment behind
# requireAuth and not a URL on the child's row: a link is fetched by
# whoever holds it, and row level security protects the ROW.
eq photo 'an anonymous caller cannot fetch it' '401' \
  "$(req GET "/api/v1/children/$CHILD_A/photo")"
eq photo 'the centre can' '200' \
  "$(req GET "/api/v1/children/$CHILD_A/photo" '' "$ADMIN")"
eq photo 'and it is not cached anywhere' 'yes' \
  "$(case "$(hdr Cache-Control)" in *no-store*) echo yes;; *) echo "no: $(hdr Cache-Control)";; esac)"
eq photo 'nor sniffed into another type' 'nosniff' "$(hdr X-Content-Type-Options)"

# A document is not a portrait. The refusal is by TYPE, and it is the
# type the schema checks - not the extension the caller claimed.
eq photo 'a PDF is not a photograph' '415' \
  "$(reqfile POST "/api/v1/children/$CHILD_A/photo" "$TMP/a10.pdf" 'application/pdf' "$ADMIN")"
eq photo 'and still one photograph on file' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.attachments WHERE child_id=$CHILD_A AND active_flg")"

# =====================================================================
# A MEMBER OF STAFF: PHOTOGRAPH AND DOCUMENTS
# =====================================================================
eq staff 'a staff photograph needs an identity' '401' \
  "$(req GET "/api/v1/users/$USER_TH/photo")"
eq staff 'there is none yet' '404' \
  "$(req GET "/api/v1/users/$USER_TH/photo" '' "$ADMIN")"
eq staff 'the centre uploads one' '201' \
  "$(reqfile POST "/api/v1/users/$USER_TH/photo" "$TMP/a10.jpg" 'image/jpeg' "$ADMIN")"
eq staff 'and it comes back' '200' \
  "$(req GET "/api/v1/users/$USER_TH/photo" '' "$ADMIN")"
eq staff 'staff without STAFF.MANAGE may not upload' '403' \
  "$(reqfile POST "/api/v1/users/$USER_ADMIN/photo" "$TMP/a10.jpg" 'image/jpeg' "$THERAPIST")"

eq staff 'a personnel document is accepted' '201' \
  "$(reqfile POST "/api/v1/users/$USER_TH/documents" "$TMP/a10.jpg" 'image/jpeg' "$ADMIN" 'doc_type' 'ID')"
eq staff 'and the same right is asked for it' '403' \
  "$(reqfile POST "/api/v1/users/$USER_ADMIN/documents" "$TMP/a10.jpg" 'image/jpeg' "$THERAPIST" 'doc_type' 'ID')"
eq staff 'an anonymous caller may not upload' '401' \
  "$(reqfile POST "/api/v1/users/$USER_TH/documents" "$TMP/a10.jpg" 'image/jpeg' '' 'doc_type' 'ID')"

# =====================================================================
# PASSWORDS
# =====================================================================
eq pw 'changing a password needs an identity' '401' \
  "$(req POST /api/v1/auth/password '{"current_password":"x","new_password":"a10-new-pw-123456"}')"

# Asserted by CODE, not by status. A 401 here could also mean the token
# expired, and "your session ended" sends a person somewhere different
# from "that is not your password".
eq pw 'the current password must be right' '401' \
  "$(req POST /api/v1/auth/password '{"current_password":"not-the-password","new_password":"a10-new-pw-123456"}' "$THERAPIST")"
eq pw 'and says which of the two it was' 'BAD_CURRENT_PASSWORD' "$(jstr "$BODY" code)"

eq pw 'a setup code is issued by the centre' '201' \
  "$(req POST "/api/v1/users/$USER_TH/password-setup" '{}' "$ADMIN")"
SETUP_CODE="$(jstr "$BODY" setup_code)"
ok_if pw 'and a code came back' "$([ -n "$SETUP_CODE" ] && echo 0 || echo 1)" 'no setup_code in the response'

# The code is stored hashed. It is a password reset in an envelope: a
# readable copy in that table is a copy of every staff account in the
# centre, and the column is named token_hash for that reason.
eq pw 'the code is not stored in the clear' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.password_setups WHERE token_hash = '$SETUP_CODE'")"
eq pw 'but a row was written for it' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.password_setups p JOIN hbh.users u ON u.user_id=p.user_id WHERE u.username='a10_therapist' AND p.consumed_at IS NULL")"

eq pw 'issuing one for somebody else needs USER.MANAGE' '403' \
  "$(req POST "/api/v1/users/$USER_ADMIN/password-setup" '{}' "$THERAPIST")"
eq pw 'redeeming a code nobody issued is refused' '400' \
  "$(req POST /api/v1/auth/password-setup '{"username":"a10_therapist","setup_code":"0000000000000000000000000000000000000000","new_password":"a10-other-pw-123456"}')"
eq pw 'and the account still has its password' 't' \
  "$(psqlq "SELECT password_hash IS NOT NULL FROM hbh.users WHERE username='a10_therapist'")"

# =====================================================================
# A ROLE'S PERMISSIONS
#
# WHY THE LAST ONE IS NOT AN HTTP CALL. hbh.set_role_permissions is
# guarded against a change that would leave nobody holding USER.MANAGE -
# the right that grants rights - because no screen in this product could
# ever put it back. Asserting that over HTTP means asking the shared
# database to perform the change and trusting the guard to stop it; if
# the guard ever failed, the suite would not report a failure, it would
# CAUSE one, permanently, for every session using this database.
#
# So the destructive case runs inside a transaction that is rolled back.
# And it runs with SET CONSTRAINTS ALL IMMEDIATE, because the guard is a
# DEFERRED constraint trigger: it fires at COMMIT, and a rolled-back
# probe never reaches one. Without that line the change appears to be
# ACCEPTED and the guard appears to be missing - which is exactly what
# the first version of this check reported, wrongly.
# =====================================================================
eq roles 'an anonymous caller may not edit a role' '401' \
  "$(req PUT /api/v1/roles/CENTER_ADMIN/permissions '{"permission_codes":["USER.MANAGE"]}')"
eq roles 'staff without USER.MANAGE may not either' '403' \
  "$(req PUT /api/v1/roles/THERAPIST/permissions '{"permission_codes":["CHILD.VIEW_ALL"]}' "$THERAPIST")"
# Two refusals with two codes, and the difference is the point: a screen
# told "no such permission" has a typo in its list, one told "no such
# role" is pointed at a role this centre does not have. One shared code
# would send both to the same dead end.
eq roles 'an unknown permission is named, not skipped' '400' \
  "$(req PUT /api/v1/roles/THERAPIST/permissions '{"permission_codes":["NO.SUCH.PERMISSION"]}' "$ADMIN")"
eq roles 'and says it was the permission' 'NO_SUCH_PERMISSION' "$(jstr "$BODY" code)"
eq roles 'an unknown role is refused' '400' \
  "$(req PUT /api/v1/roles/NO_SUCH_ROLE/permissions '{"permission_codes":["CHILD.VIEW_ALL"]}' "$ADMIN")"
eq roles 'and says it was the role' 'NO_SUCH_ROLE' "$(jstr "$BODY" code)"
eq roles 'THERAPIST still holds its grants' 't' \
  "$(psqlq "SELECT count(*) > 3 FROM hbh.role_permissions rp JOIN hbh.roles r ON r.role_id=rp.role_id WHERE r.code='THERAPIST' AND r.center_id=(SELECT center_id FROM hbh.centers WHERE code='HBH') AND rp.active_flg")"

# Through a FILE and psqlf, not psqlq: psqlq sends stderr to /dev/null,
# and the SQLSTATE this check exists to read arrives on stderr. Reading
# it with psqlq returns an empty string, which compares unequal to
# everything and reports a failure that has nothing to do with the guard.
cat > "$TMP/lastadmin.sql" <<'LASTADMIN'
BEGIN;
SELECT set_config('hbh.user_id', 'a10_admin', false);
SET CONSTRAINTS ALL IMMEDIATE;
DO $probe$
BEGIN
  PERFORM hbh.set_role_permissions('CENTER_ADMIN', ARRAY['CHILD.VIEW_ALL']);
  RAISE EXCEPTION 'ACCEPTED_NO_GUARD';
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'RESULT=%', SQLSTATE;
END
$probe$;
ROLLBACK;
LASTADMIN
eq roles 'the last USER.MANAGE cannot be taken away' 'HB190' \
  "$(psqlf "$TMP/lastadmin.sql" | grep -oE 'RESULT=[A-Z0-9]+' | head -1 | cut -d= -f2)"
eq roles 'and CENTER_ADMIN is untouched afterwards' 't' \
  "$(psqlq "SELECT EXISTS (SELECT 1 FROM hbh.role_permissions rp JOIN hbh.roles r ON r.role_id=rp.role_id JOIN hbh.permissions p ON p.permission_id=rp.permission_id WHERE r.code='CENTER_ADMIN' AND p.code='USER.MANAGE' AND rp.active_flg)")"

# =====================================================================
# THE DOOR
# =====================================================================
eq door 'no DELETE grant on any of these tables' '0' \
  "$(psqlq "SELECT count(*) FROM information_schema.role_table_grants WHERE grantee='hbh_app' AND table_schema='hbh' AND table_name IN ('attachments','staff_documents','role_permissions','password_setups') AND privilege_type='DELETE'")"
eq door 'an anonymous connection reads no attachment' '0' \
  "$(psqlapp "SELECT count(*) FROM hbh.attachments")"

# A SHARPER ANSWER THAN ZERO ROWS, and asserted as such. Attachments are
# readable by hbh_app and filtered to nothing by the policy; setup codes
# are not readable AT ALL - the role holds no SELECT on that table, so
# the refusal is a grant refusal and arrives as an error, not a count.
# Asserting '0' here passed on the ERROR TEXT being unequal to zero,
# which is the wrong reason to be green.
eq door 'the app role cannot read setup codes at all' 'yes' \
  "$(case "$(psqlapp "SELECT count(*) FROM hbh.password_setups")" in *"permission denied"*) echo yes;; *) echo "no: it returned rows";; esac)"
eq door 'and holds no privilege on that table' '0' \
  "$(psqlq "SELECT count(*) FROM information_schema.role_table_grants WHERE grantee='hbh_app' AND table_schema='hbh' AND table_name='password_setups'")"

# =====================================================================
# CLEANUP - a recorded check like any other
# =====================================================================
OUT="$(psqlf "$ROOT/tests/fixtures/a10_teardown.sql")"
RC=$?
if [ "$RC" != "0" ]; then chk cleanup 'fixture removed' 1 "$OUT"; else chk cleanup 'fixture removed' 0; fi
eq cleanup 'no attachment survived' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.attachments WHERE child_id IN (${CHILD_A:-0},${CHILD_B:-0})")"
eq cleanup 'no setup code survived' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.password_setups p JOIN hbh.users u ON u.user_id=p.user_id WHERE u.username LIKE 'a10\\_%'")"

verdict 'API PHASE 10'
