#!/usr/bin/env bash
# =====================================================================
# Hand By Hand (new) - API PHASE 7 acceptance suite
#
# Must print:  API PHASE 7 ACCEPTED
#
#   bash scripts/api.sh verify 7
#
# The therapist's profile - what a family reads about the person who
# will sit with their child.
#
# Four decisions were made when the tables were created because they
# could not be made afterwards, and this suite exists to prove each one
# still holds:
#
#   1. A certificate's scan is private unless THAT certificate says
#      otherwise. An Egyptian certificate photographed usually carries a
#      national ID number, a date of birth and a signature.
#   2. Publishing needs the therapist's own recorded consent - a name,
#      an instant and a text version, not a permission.
#   3. The admin override is pinned to user_type, not to a permission.
#      The alternative is the can_close_session defect: two rights that
#      belong in THERAPIST for good reasons, together granting authority
#      over colleagues.
#   4. The year is stored and the experience derived.
#
# THE FIXTURE CREATES NO CONSENT. Consenting is the thing under test.
#
# The harness and the five rules it enforces are in tests/api/lib.sh.
# =====================================================================

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "============== api phase 7 - the therapist's profile =============="
echo "base: $API_BASE"
echo

# =====================================================================
# FIXTURE - asserted by name, before any test runs
# =====================================================================
OUT="$(psqlf "$ROOT/tests/fixtures/a7_teardown.sql")"
RC=$?
if [ "$RC" != "0" ]; then chk fixture 'previous fixture removed' 1 "$OUT"; else chk fixture 'previous fixture removed' 0; fi

OUT="$(psqlf "$ROOT/tests/fixtures/a7_fixture.sql")"
RC=$?
if [ "$RC" != "0" ]; then chk fixture 'fixture applied' 1 "$OUT"; else chk fixture 'fixture applied' 0; fi

TH="$(psqlq "SELECT t.therapist_id FROM hbh.therapists t JOIN hbh.users u ON u.user_id=t.user_id WHERE u.username='a7_therapist'")"
OTHER="$(psqlq "SELECT t.therapist_id FROM hbh.therapists t JOIN hbh.users u ON u.user_id=t.user_id WHERE u.username='a7_other'")"

for v in TH OTHER; do
  eval "val=\$$v"
  ok_if fixture "$v is known" "$([ -n "$val" ] && echo 0 || echo 1)" "$v is empty"
done

eq fixture 'service answers /healthz' '200' "$(req GET /healthz)"
for m in 0033 0034; do
  eq fixture "migration $m is applied" 't' "$(psqlq "SELECT hbh.migration_applied('$m')")"
done

ADMIN="$(staff_login a7_admin a7-admin-pw-123456)"
THERAPIST="$(staff_login a7_therapist a7-therapist-pw-123456)"
COLLEAGUE="$(staff_login a7_other a7-other-pw-123456)"
PARENT="$(login 01500000073)"
ok_if fixture 'the administrator signed in' "$([ -n "$ADMIN" ] && echo 0 || echo 1)" 'no token for a7_admin'
ok_if fixture 'the therapist signed in'     "$([ -n "$THERAPIST" ] && echo 0 || echo 1)" 'no token for a7_therapist'
ok_if fixture 'the colleague signed in'     "$([ -n "$COLLEAGUE" ] && echo 0 || echo 1)" 'no token for a7_other'
ok_if fixture 'the guardian signed in'      "$([ -n "$PARENT" ] && echo 0 || echo 1)" 'no token for a7_parent'

# =====================================================================
# WHO MAY EDIT
#
# Two justifications, two branches. The colleague is the check that
# matters: they are a THERAPIST, like the owner of the profile, and the
# ONLY thing separating them is whose profile it is.
# =====================================================================
BIO='{"bio_ar":"أعمل مع الأطفال من عمر سنتين، وأركّز على النطق المبكّر.","practice_since_year":2015,"age_from_mon":24,"age_to_mon":96}'

# THE PROFILE COLUMNS HAVE THEIR OWN ENDPOINT, and finding out why was
# the first thing this suite did. Adding them to the generic resource
# meant a therapist could only reach their own biography through a
# policy that demands STAFF.MANAGE - and widening THAT policy would have
# handed them status, user_id and branch_id too, because row level
# security grants rows and not columns.
eq edit 'a therapist edits their own profile' '204' \
  "$(req PATCH "/api/v1/therapists/$TH/profile" "$BIO" "$THERAPIST")"
eq edit 'the year was stored'  '2015' "$(psqlq "SELECT practice_since_year FROM hbh.therapists WHERE therapist_id=$TH")"
eq edit 'and the age range in MONTHS' '24' "$(psqlq "SELECT age_from_mon FROM hbh.therapists WHERE therapist_id=$TH")"

# Experience is DERIVED. A stored count goes stale every January and
# nothing in the system knows it has - the same reason a child's age
# comes from birth_date.
eq edit 'there is no stored experience column' '0' \
  "$(psqlq "SELECT count(*) FROM information_schema.columns WHERE table_schema='hbh' AND table_name='therapists' AND column_name ~ 'experience|years_of'")"

# The colleague is a THERAPIST, exactly like the owner of this profile.
# The only thing separating them is whose profile it is - which is why
# the override is pinned to user_type and not to a permission they both
# hold.
eq edit 'a colleague may NOT edit this profile' '403' \
  "$(req PATCH "/api/v1/therapists/$TH/profile" '{"bio_ar":"كتبها زميل"}' "$COLLEAGUE")"
eq edit 'and nothing moved' 't' \
  "$(psqlq "SELECT bio_ar NOT LIKE '%زميل%' FROM hbh.therapists WHERE therapist_id=$TH")"
eq edit 'the centre may edit anybody' '204' \
  "$(req PATCH "/api/v1/therapists/$TH/profile" '{"bio_ar":"حرّرتها الإدارة"}' "$ADMIN")"
eq edit 'a guardian may not edit at all' '403' \
  "$(req PATCH "/api/v1/therapists/$TH/profile" '{"bio_ar":"كتبها ولي أمر"}' "$PARENT")"

# "Not mentioned" and "set to empty" are different requests. A screen
# editing the biography must not blank an age range it never displayed.
eq edit 'an unmentioned field is left alone' '24' \
  "$(psqlq "SELECT age_from_mon FROM hbh.therapists WHERE therapist_id=$TH")"
eq edit 'clearing is said out loud' '204' \
  "$(req PATCH "/api/v1/therapists/$TH/profile" '{"clear":["age_from_mon"]}' "$THERAPIST")"
eq edit 'and only then is it emptied' 't' \
  "$(psqlq "SELECT age_from_mon IS NULL FROM hbh.therapists WHERE therapist_id=$TH")"
eq edit 'a field outside the profile cannot be cleared' '400' \
  "$(req PATCH "/api/v1/therapists/$TH/profile" '{"clear":["status"]}' "$THERAPIST")"
eq edit 'and the status is untouched' 'ACTIVE' \
  "$(psqlq "SELECT status FROM hbh.therapists WHERE therapist_id=$TH")"

# =====================================================================
# CONSENT - and it is not a permission
# =====================================================================
eq consent 'publishing with no consent is refused' '409' \
  "$(req POST "/api/v1/therapists/$TH/publish" '' "$ADMIN")"
eq consent 'and says what is missing' 'CONSENT_REQUIRED' "$(jstr "$BODY" code)"
eq consent 'the profile is still a draft' 'DRAFT' \
  "$(psqlq "SELECT profile_status FROM hbh.therapists WHERE therapist_id=$TH")"

# The administrator holds every permission the centre has, and still
# cannot agree on somebody else's behalf. A consent given for you is not
# a consent.
eq consent 'the centre may not consent for a therapist' '403' \
  "$(req POST "/api/v1/therapists/$TH/consent" '' "$ADMIN")"
eq consent 'and is told whose consent it is' 'NOT_YOUR_CONSENT' "$(jstr "$BODY" code)"
eq consent 'a colleague may not consent for them either' '403' \
  "$(req POST "/api/v1/therapists/$TH/consent" '' "$COLLEAGUE")"
eq consent 'still nothing recorded' 't' \
  "$(psqlq "SELECT consent_at IS NULL FROM hbh.therapists WHERE therapist_id=$TH")"

eq consent 'the therapist consents for themselves' '204' \
  "$(req POST "/api/v1/therapists/$TH/consent" '{"text_version":"v1"}' "$THERAPIST")"
# RECORDED means who, when, and to what. A boolean would say somebody
# once clicked; these three answer a question asked a year later.
eq consent 'the instant was recorded' 't' \
  "$(psqlq "SELECT consent_at IS NOT NULL FROM hbh.therapists WHERE therapist_id=$TH")"
eq consent 'and who gave it'          't' \
  "$(psqlq "SELECT consent_by IS NOT NULL FROM hbh.therapists WHERE therapist_id=$TH")"
eq consent 'and which text they agreed to' 'v1' \
  "$(psqlq "SELECT consent_text_version FROM hbh.therapists WHERE therapist_id=$TH")"

eq publish 'now it publishes' '204' "$(req POST "/api/v1/therapists/$TH/publish" '' "$ADMIN")"
eq publish 'and says so'  'PUBLISHED' \
  "$(psqlq "SELECT profile_status FROM hbh.therapists WHERE therapist_id=$TH")"
eq publish 'with a publisher and an instant' 't' \
  "$(psqlq "SELECT published_at IS NOT NULL AND published_by IS NOT NULL FROM hbh.therapists WHERE therapist_id=$TH")"
eq publish 'publishing twice is refused' '409' \
  "$(req POST "/api/v1/therapists/$TH/publish" '' "$ADMIN")"
eq publish 'and names the reason' 'ALREADY_PUBLISHED' "$(jstr "$BODY" code)"

# The guard below the API. Even a direct UPDATE cannot publish a profile
# nobody consented to - the rule lives in the trigger, not in Go.
OUT="$(psqlq "UPDATE hbh.therapists SET profile_status='DRAFT' WHERE therapist_id=$OTHER; UPDATE hbh.therapists SET profile_status='PUBLISHED' WHERE therapist_id=$OTHER" 2>&1)"
eq publish 'a direct UPDATE cannot publish without consent' 'DRAFT' \
  "$(psqlq "SELECT profile_status FROM hbh.therapists WHERE therapist_id=$OTHER")"

# =====================================================================
# LANGUAGES
#
# "Speaks" and "runs sessions in" are separate facts, and in a speech
# therapy centre the second is a clinical matching criterion.
# =====================================================================
eq lang 'a language can be added' '204' \
  "$(req PUT "/api/v1/therapists/$TH/languages" '{"lang_code":"ar","level_code":"NATIVE","is_native":true,"runs_sessions":true}' "$THERAPIST")"
eq lang 'and a second one' '204' \
  "$(req PUT "/api/v1/therapists/$TH/languages" '{"lang_code":"en","level_code":"GOOD","is_native":false,"runs_sessions":false}' "$THERAPIST")"

eq lang 'they read back' '200' "$(req GET "/api/v1/therapists/$TH/languages" '' "$THERAPIST")"
eq lang 'both of them'   '2'   "$(jnum "$BODY" total)"
ok_if lang 'and the two facts are separate on the row' \
  "$(grep -q '"runs_sessions"' "$BODY" && echo 0 || echo 1)" 'runs_sessions is not on the row'

# At most one native language, enforced by a partial unique index. A
# CHECK sees one row and cannot count the others.
eq lang 'a SECOND native language is refused' '400' \
  "$(req PUT "/api/v1/therapists/$TH/languages" '{"lang_code":"fr","level_code":"NATIVE","is_native":true}' "$THERAPIST")"
eq lang 'and there is still exactly one' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.therapist_languages WHERE therapist_id=$TH AND is_native_flg AND active_flg")"

# Re-sending a language is an EDIT, not a duplicate: the pair is the key.
eq lang 'sending the same language again edits it' '204' \
  "$(req PUT "/api/v1/therapists/$TH/languages" '{"lang_code":"en","level_code":"FLUENT","runs_sessions":true}' "$THERAPIST")"
eq lang 'and the level changed'  'FLUENT' \
  "$(psqlq "SELECT level_code FROM hbh.therapist_languages WHERE therapist_id=$TH AND lang_code='en'")"
eq lang 'without creating a second row' '2' \
  "$(psqlq "SELECT count(*) FROM hbh.therapist_languages WHERE therapist_id=$TH")"

eq lang 'a colleague may not add one' '403' \
  "$(req PUT "/api/v1/therapists/$TH/languages" '{"lang_code":"de"}' "$COLLEAGUE")"
eq lang 'and none was added' '2' \
  "$(psqlq "SELECT count(*) FROM hbh.therapist_languages WHERE therapist_id=$TH")"

eq lang 'a language can be removed' '204' \
  "$(req DELETE "/api/v1/therapists/$TH/languages/en" '' "$THERAPIST")"
eq lang 'archived, not deleted' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.therapist_languages WHERE therapist_id=$TH AND lang_code='en' AND NOT active_flg")"
eq lang 'removing it twice is a 404' '404' \
  "$(req DELETE "/api/v1/therapists/$TH/languages/en" '' "$THERAPIST")"

# An archived row keeps is_native_flg, and must not block a new one.
eq lang 'the archived native slot does not block a new native' '204' \
  "$(req DELETE "/api/v1/therapists/$TH/languages/ar" '' "$THERAPIST")"
eq lang 'a new native language is accepted' '204' \
  "$(req PUT "/api/v1/therapists/$TH/languages" '{"lang_code":"fr","level_code":"NATIVE","is_native":true}' "$THERAPIST")"

# =====================================================================
# CERTIFICATES - the decision that could not be made later
# =====================================================================
CERT='{"title_ar":"دبلومة تخاطب","issuer_ar":"جامعة القاهرة","year_awarded":2016,"registration_no":"REG-A7-1"}'
eq cert 'a certificate can be added' '201' \
  "$(req POST "/api/v1/therapists/$TH/certificates" "$CERT" "$THERAPIST")"
CERT_ID="$(jnum "$BODY" certificate_id)"
ok_if cert 'and has an identifier' "$([ -n "$CERT_ID" ] && echo 0 || echo 1)" 'no certificate_id'

# THE DEFAULT. Not "we chose false" in a comment - false in the row.
eq cert 'its image is private by default' 'f' \
  "$(psqlq "SELECT is_image_public FROM hbh.therapist_certificates WHERE certificate_id=${CERT_ID:-0}")"

eq cert 'the family sees the certificate' '200' \
  "$(req GET "/api/v1/therapists/$TH/certificates" '' "$PARENT")"
ok_if cert 'with its title, which is what reassures them' \
  "$(grep -q 'دبلومة تخاطب' "$BODY" && echo 0 || echo 1)" 'the title is missing'
ok_if cert 'and NOT the registration number' \
  "$(grep -q 'REG-A7-1' "$BODY" && echo 1 || echo 0)" 'a registration number reached a guardian'

eq cert 'the therapist sees their own number' '200' \
  "$(req GET "/api/v1/therapists/$TH/certificates" '' "$THERAPIST")"
ok_if cert 'as they must' \
  "$(grep -q 'REG-A7-1' "$BODY" && echo 0 || echo 1)" 'the therapist cannot see their own registration number'

# Releasing an image is its OWN act. Folded into a general edit it would
# ride along with a typo correction.
eq cert 'the image flag needs an explicit body' '400' \
  "$(req PATCH "/api/v1/certificates/${CERT_ID:-0}/image" '{}' "$THERAPIST")"
eq cert 'and names the field' 'is_image_public' "$(jstr "$BODY" field)"

# It cannot be public when there is no image: without that constraint
# the flag sits true on an empty row and means something the moment a
# scan is attached.
eq cert 'an image cannot be public when there is none' '400' \
  "$(req PATCH "/api/v1/certificates/${CERT_ID:-0}/image" '{"is_image_public":true}' "$THERAPIST")"
eq cert 'and it stayed private' 'f' \
  "$(psqlq "SELECT is_image_public FROM hbh.therapist_certificates WHERE certificate_id=${CERT_ID:-0}")"

eq cert 'a guardian may not add a certificate' '403' \
  "$(req POST "/api/v1/therapists/$TH/certificates" '{"title_ar":"شهادة مزوّرة"}' "$PARENT")"
eq cert 'a colleague may not either' '403' \
  "$(req POST "/api/v1/therapists/$TH/certificates" '{"title_ar":"شهادة زميل"}' "$COLLEAGUE")"
eq cert 'and only one certificate exists' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.therapist_certificates WHERE therapist_id=$TH")"

# Two unrecorded registration numbers are not a duplicate. This is the
# defect that reached production in Oracle - a UNIQUE that treated every
# NULL as equal refused the SECOND child with no national ID - and the
# test is TWO ROWS ON THE SAME SIDE of the rule, not one of each.
eq cert 'a certificate with no number is accepted' '201' \
  "$(req POST "/api/v1/therapists/$TH/certificates" '{"title_ar":"دورة تدريبية"}' "$THERAPIST")"
eq cert 'and a SECOND one with no number too' '201' \
  "$(req POST "/api/v1/therapists/$TH/certificates" '{"title_ar":"دورة أخرى"}' "$THERAPIST")"
eq cert 'both were kept' '2' \
  "$(psqlq "SELECT count(*) FROM hbh.therapist_certificates WHERE therapist_id=$TH AND registration_no IS NULL")"

# =====================================================================
# WHAT A FAMILY READS
#
# The published/draft split is the same ladder as a progress report: the
# version the centre released, not the paragraph somebody is editing at
# lunchtime.
# =====================================================================
eq read 'the family reads the published profile' '200' \
  "$(req GET "/api/v1/therapists/$TH/languages" '' "$PARENT")"
ok_if read 'and it has content' \
  "$([ "$(jnum "$BODY" total)" -ge 1 ] 2>/dev/null && echo 0 || echo 1)" 'the published profile is empty to a family'

# The colleague's profile is still a DRAFT, so a family sees nothing of
# it - not an error, an empty list.
eq read 'an unpublished profile shows a family nothing' '200' \
  "$(req GET "/api/v1/therapists/$OTHER/languages" '' "$PARENT")"
eq read 'and the list is empty' '0' "$(jnum "$BODY" total)"

# 0031 still holds on the profile columns added since.
eq read 'a family listing therapists sees no mobile' '200' "$(req GET /api/v1/therapists '' "$PARENT")"
ok_if read 'nor a mobile number' \
  "$(grep -qE '"mobile":"[0-9]' "$BODY" && echo 1 || echo 0)" 'a therapist mobile reached a guardian'
ok_if read 'nor who consented' \
  "$(grep -qE '"consent_by":[0-9]' "$BODY" && echo 1 || echo 0)" 'consent_by reached a guardian'
ok_if read 'but the biography is theirs to read' \
  "$(grep -q '"bio_ar"' "$BODY" && echo 0 || echo 1)" 'the biography is hidden from families'

# =====================================================================
# A DRAFT PROFILE IS NOT PUBLIC EITHER - AND THE COLUMNS ARE THE HALF
# THAT WAS FORGOTTEN
#
# The three profile TABLES carried "published, or staff, or its owner"
# from the start. The columns on the therapist ROW did not - so a draft
# biography, the most personal field on the profile, reached every
# family at the centre before its author had agreed to publish it.
# Confirmed against a running build: the paragraph came back verbatim.
#
# The tables were guarding the side rooms while the front door stood
# open. These checks are the front door.
# =====================================================================
DRAFT_BIO='نبذة لم تُنشر بعد ولا يجوز أن تصل أسرة'
psqlq "SELECT set_config('hbh.user_id','a7_admin',false)" >/dev/null
psqlq "UPDATE hbh.therapists SET bio_ar='$DRAFT_BIO', practice_since_year=2011 WHERE therapist_id=$OTHER" >/dev/null

eq draft 'the colleague profile is still a draft' 'DRAFT' \
  "$(psqlq "SELECT profile_status FROM hbh.therapists WHERE therapist_id=$OTHER")"

eq draft 'a family may list the therapists' '200' "$(req GET /api/v1/therapists '' "$PARENT")"
ok_if draft 'and does NOT receive the unpublished biography' \
  "$(grep -q "$DRAFT_BIO" "$BODY" && echo 1 || echo 0)" \
  'a draft biography reached a guardian'
ok_if draft 'nor the unpublished practice year' \
  "$(grep -q '"practice_since_year":2011' "$BODY" && echo 1 || echo 0)" \
  'a draft practice year reached a guardian'

eq draft 'the same row read singly' '200' "$(req GET "/api/v1/therapists/$OTHER" '' "$PARENT")"
ok_if draft 'hides it there too' \
  "$(grep -q "$DRAFT_BIO" "$BODY" && echo 1 || echo 0)" \
  'the single read leaked what the list hid'
ok_if draft 'while still naming the person' \
  "$(grep -q '"full_name_ar"' "$BODY" && echo 0 || echo 1)" 'a family cannot see who the therapist is at all'

# The owner and the centre must still see their own draft, or the edit
# screen has nothing to edit.
eq draft 'the colleague reads their own draft' '200' \
  "$(req GET "/api/v1/therapists/$OTHER" '' "$COLLEAGUE")"
ok_if draft 'and it is all there' \
  "$(grep -q "$DRAFT_BIO" "$BODY" && echo 0 || echo 1)" 'a therapist cannot read their own draft'
eq draft 'the centre reads it as well' '200' "$(req GET "/api/v1/therapists/$OTHER" '' "$ADMIN")"
ok_if draft 'as it must to review before publishing' \
  "$(grep -q "$DRAFT_BIO" "$BODY" && echo 0 || echo 1)" 'the centre cannot read a draft it is asked to publish'

# =====================================================================
# WITHDRAWING CONSENT TAKES THE PAGE DOWN WITH IT
#
# A consent that can be withdrawn while the page stays up is not a
# consent, and leaving the two to be done separately means the second
# gets forgotten.
# =====================================================================
eq withdraw 'the centre may not withdraw for them' '403' \
  "$(req DELETE "/api/v1/therapists/$TH/consent" '' "$ADMIN")"
eq withdraw 'the therapist withdraws their own' '204' \
  "$(req DELETE "/api/v1/therapists/$TH/consent" '' "$THERAPIST")"
eq withdraw 'the consent is gone'  't' \
  "$(psqlq "SELECT consent_at IS NULL FROM hbh.therapists WHERE therapist_id=$TH")"
eq withdraw 'and the page came down WITH it' 'WITHDRAWN' \
  "$(psqlq "SELECT profile_status FROM hbh.therapists WHERE therapist_id=$TH")"
eq withdraw 'so the family sees nothing again' '200' \
  "$(req GET "/api/v1/therapists/$TH/languages" '' "$PARENT")"
eq withdraw 'an empty list, not an error' '0' "$(jnum "$BODY" total)"
eq withdraw 'and it cannot be republished without a new consent' '409' \
  "$(req POST "/api/v1/therapists/$TH/publish" '' "$ADMIN")"
eq withdraw 'for the reason that matters' 'CONSENT_REQUIRED' "$(jstr "$BODY" code)"

# =====================================================================
# STRUCTURE
# =====================================================================
eq structure 'no DELETE grant on the profile tables' '0' \
  "$(psqlq "SELECT count(*) FROM information_schema.role_table_grants WHERE grantee='hbh_app' AND table_schema='hbh' AND privilege_type='DELETE' AND table_name LIKE 'therapist_%'")"
eq structure 'every profile table has a change audit' '(none)' \
  "$(psqlq "SELECT coalesce(string_agg(g.table_name, ', '), '(none)')
            FROM  (SELECT DISTINCT table_name FROM information_schema.role_table_grants
                    WHERE grantee='hbh_app' AND table_schema='hbh'
                    AND   privilege_type IN ('INSERT','UPDATE')
                    AND   table_name LIKE 'therapist_%') g
            WHERE NOT EXISTS (SELECT 1 FROM pg_trigger t
                              JOIN pg_class c ON c.oid = t.tgrelid
                              JOIN pg_namespace n ON n.oid = c.relnamespace
                              JOIN pg_proc p ON p.oid = t.tgfoid
                              WHERE n.nspname='hbh' AND c.relname = g.table_name
                              AND   NOT t.tgisinternal AND p.prosrc LIKE '%hbh.audit_log%')")"
eq structure 'an anonymous connection reads no certificate' '0' \
  "$(psqlapp "SELECT count(*) FROM hbh.therapist_certificates")"
eq structure 'nor a language' '0' \
  "$(psqlapp "SELECT count(*) FROM hbh.therapist_languages")"

# =====================================================================
# ADMINISTERING USERS AND ROLES
#
# The mechanism by which every other permission in this system is handed
# out. The owner decided one thing explicitly - an administrator MAY
# appoint another - so the accountability has to come from the record
# instead, and half of these checks are that record.
# =====================================================================
eq admin 'the centre lists its people' '200' "$(req GET /api/v1/users '' "$ADMIN")"
ok_if admin 'with the roles each one holds' \
  "$(grep -q '"roles"' "$BODY" && echo 0 || echo 1)" 'no roles on the user rows'
ok_if admin 'and NEVER a password hash' \
  "$(grep -q 'password_hash' "$BODY" && echo 1 || echo 0)" 'a password hash reached a client'
ok_if admin 'nor how often somebody mistyped their password' \
  "$(grep -q 'failed_login_cnt' "$BODY" && echo 1 || echo 0)" 'failed_login_cnt reached a client'
ok_if admin 'but whether they can sign in at all' \
  "$(grep -q '"has_password"' "$BODY" && echo 0 || echo 1)" 'no has_password flag'

# A TYPED WILDCARD IS A CHARACTER, NOT A WILDCARD.
#
# The term has always been a bound parameter, so this was never injection.
# It was the quieter defect underneath: until the term was escaped, an
# administrator who typed a single '%' was handed EVERY account in the
# centre, and '_' stood for any character - which matters more here than
# anywhere else, because every username in this schema HAS an underscore
# in it, so the wrong colleague came back for a search that looked right.
#
# The total is read from the response rather than counted out of it, and
# the unfiltered total is taken first: '0' proves nothing about escaping on
# a list that had nobody in it to over-match.
LISTED="$(req GET /api/v1/users '' "$ADMIN" >/dev/null; jnum "$BODY" total)"
ok_if admin 'the centre has people for a wildcard to over-match' \
  "$([ "${LISTED:-0}" -gt 0 ] && echo 0 || echo 1)" \
  'the user list is empty, so the wildcard checks below would pass on nothing'

eq admin 'a search for % is accepted, not refused' '200' \
  "$(req GET '/api/v1/users?q=%25' '' "$ADMIN")"
eq admin 'and matches nobody rather than everybody' '0' "$(jnum "$BODY" total)"

# ONE CHARACTER OF a7_therapist SWAPPED FOR AN UNDERSCORE. While '_' was a
# wildcard this term found her; now it is a character, it finds nobody -
# which is the only shape that tells the two behaviours apart. A term with
# no underscore at all would match nothing either way and prove nothing.
eq admin 'a name with _ standing in for a letter is accepted' '200' \
  "$(req GET '/api/v1/users?q=a7_ther_pist' '' "$ADMIN")"
eq admin 'and matches nobody, because _ is a character now' '0' "$(jnum "$BODY" total)"

# AND THE ESCAPE DID NOT BREAK THE REAL SEARCH. Escaping is only half the
# fix: a wrong ESCAPE clause would refuse every username in this schema,
# and the check above would stay green while it happened.
eq admin 'the real username still searches' '200' \
  "$(req GET '/api/v1/users?q=a7_therapist' '' "$ADMIN")"
ok_if admin 'and finds her, underscore and all' \
  "$([ "$(jnum "$BODY" total)" -gt 0 ] && echo 0 || echo 1)" \
  'escaping the underscore lost a username that really contains one'

# No USER.MANAGE means the policy filters rows: an empty list, not a
# refusal. The same fail-closed shape as everywhere else.
eq admin 'a therapist sees no user list' '200' "$(req GET /api/v1/users '' "$THERAPIST")"
eq admin 'because the policy filters rows' '0' "$(jnum "$BODY" total)"
eq admin 'a guardian sees none either'     '200' "$(req GET /api/v1/users '' "$PARENT")"
eq admin 'empty as well'                   '0'   "$(jnum "$BODY" total)"

# The roles screen reads the model from the database. A console holding
# its own copy would go silently wrong the first time a grant changed -
# on the one screen where people go to ask this exact question.
eq admin 'the roles read back with what each may do' '200' "$(req GET /api/v1/roles '' "$ADMIN")"
ok_if admin 'including the permissions behind them' \
  "$(grep -q '"permissions"' "$BODY" && echo 0 || echo 1)" 'roles came back with no permissions'
ok_if admin 'and the four roles are there' \
  "$(grep -q 'CENTER_ADMIN' "$BODY" && echo 0 || echo 1)" 'CENTER_ADMIN is missing from the roles list'
eq admin 'and every permission the schema defines' '200' "$(req GET /api/v1/permissions '' "$ADMIN")"
ok_if admin 'named, not just coded' \
  "$(grep -q '"name_ar"' "$BODY" && echo 0 || echo 1)" 'permissions came back without names'

# CREATING AN ACCOUNT DOES NOT SET A PASSWORD, and the response says so.
# A password field on a creation screen is a password read aloud and
# written on paper.
eq admin 'the centre creates an account' '201' \
  "$(req POST /api/v1/users '{"username":"a7_new","full_name_ar":"موظّفة جديدة","user_type":"STAFF","mobile":"01500000079"}' "$ADMIN")"
NEW_USER="$(jnum "$BODY" user_id)"
ok_if admin 'and it has an identifier' "$([ -n "$NEW_USER" ] && echo 0 || echo 1)" 'no user_id'
eq admin 'the answer says it cannot sign in yet' 'false' "$(jbool "$BODY" has_password)"
eq admin 'and the row really has no password' 't' \
  "$(psqlq "SELECT password_hash IS NULL FROM hbh.users WHERE user_id=${NEW_USER:-0}")"
eq admin 'the username was taken to lower case' 'a7_new' \
  "$(psqlq "SELECT username FROM hbh.users WHERE user_id=${NEW_USER:-0}")"

eq admin 'the same username is refused' '409' \
  "$(req POST /api/v1/users '{"username":"A7_NEW","full_name_ar":"أخرى","user_type":"STAFF"}' "$ADMIN")"
eq admin 'and says which way'  'USERNAME_TAKEN' "$(jstr "$BODY" code)"
eq admin 'an unknown user type is refused' '400' \
  "$(req POST /api/v1/users '{"username":"a7_bad","full_name_ar":"س","user_type":"ROBOT"}' "$ADMIN")"
eq admin 'a therapist may not create accounts' '403' \
  "$(req POST /api/v1/users '{"username":"a7_sneak","full_name_ar":"س","user_type":"STAFF"}' "$THERAPIST")"
eq admin 'and none was created' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.users WHERE username IN ('a7_bad','a7_sneak')")"

# GRANTING IS A RECORDED ACT.
eq roles 'roles are set as a whole list' '204' \
  "$(req PUT "/api/v1/users/${NEW_USER:-0}/roles" '{"role_codes":["RECEPTION"]}' "$ADMIN")"
eq roles 'the role is held' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.user_roles ur JOIN hbh.roles r ON r.role_id=ur.role_id WHERE ur.user_id=${NEW_USER:-0} AND ur.active_flg AND r.code='RECEPTION'")"
# Who granted it, and when. The first question asked after something
# goes wrong, and a plain UPDATE could not answer it.
eq roles 'and the grant is stamped with who' 't' \
  "$(psqlq "SELECT granted_by IS NOT NULL AND granted_at IS NOT NULL FROM hbh.user_roles WHERE user_id=${NEW_USER:-0} AND active_flg")"

# The owner's decision, tested rather than assumed: the centre appoints
# its own administrators.
eq roles 'the centre may appoint another administrator' '204' \
  "$(req PUT "/api/v1/users/${NEW_USER:-0}/roles" '{"role_codes":["CENTER_ADMIN"]}' "$ADMIN")"
eq roles 'and the previous role was archived, not deleted' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.user_roles ur JOIN hbh.roles r ON r.role_id=ur.role_id WHERE ur.user_id=${NEW_USER:-0} AND NOT ur.active_flg AND r.code='RECEPTION'")"
eq roles 'so who used to hold what is still readable' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.user_roles WHERE user_id=${NEW_USER:-0} AND active_flg")"

# NOBODY CHANGES THEIR OWN ROLES. Redundant today - an administrator
# already holds everything - and the line that stops a self-promotion the
# day USER.MANAGE reaches a narrower role.
ADMIN_ID="$(psqlq "SELECT user_id FROM hbh.users WHERE username='a7_admin'")"
eq roles 'an account may not change its own roles' '409' \
  "$(req PUT "/api/v1/users/${ADMIN_ID:-0}/roles" '{"role_codes":["CENTER_ADMIN","THERAPIST"]}' "$ADMIN")"
eq roles 'and is told exactly why' 'NOT_YOUR_OWN_ROLES' "$(jstr "$BODY" code)"
eq roles 'nothing changed' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.user_roles WHERE user_id=${ADMIN_ID:-0} AND active_flg")"

eq roles 'a role that does not exist is named' '400' \
  "$(req PUT "/api/v1/users/${NEW_USER:-0}/roles" '{"role_codes":["RECEPTION","WIZARD"]}' "$ADMIN")"
eq roles 'and says so'  'NO_SUCH_ROLE' "$(jstr "$BODY" code)"
# All or nothing: the valid half of that list must not have been applied.
eq roles 'and the valid half was NOT applied' 'CENTER_ADMIN' \
  "$(psqlq "SELECT r.code FROM hbh.user_roles ur JOIN hbh.roles r ON r.role_id=ur.role_id WHERE ur.user_id=${NEW_USER:-0} AND ur.active_flg")"

# A missing key is not an empty list. Stripping somebody's access because
# a field was absent is the one mistake this endpoint must not make.
eq roles 'a missing role_codes is refused' '400' \
  "$(req PUT "/api/v1/users/${NEW_USER:-0}/roles" '{}' "$ADMIN")"
eq roles 'and the roles are untouched' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.user_roles WHERE user_id=${NEW_USER:-0} AND active_flg")"
eq roles 'an EMPTY list is accepted and means none' '204' \
  "$(req PUT "/api/v1/users/${NEW_USER:-0}/roles" '{"role_codes":[]}' "$ADMIN")"
eq roles 'and now they hold nothing' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.user_roles WHERE user_id=${NEW_USER:-0} AND active_flg")"

eq roles 'a therapist may not grant roles' '403' \
  "$(req PUT "/api/v1/users/${NEW_USER:-0}/roles" '{"role_codes":["CENTER_ADMIN"]}' "$THERAPIST")"

# EDITING AND ARCHIVING
eq admin 'a name and a number can be edited' '204' \
  "$(req PATCH "/api/v1/users/${NEW_USER:-0}" '{"full_name_ar":"موظّفة الاستقبال","status":"SUSPENDED"}' "$ADMIN")"
eq admin 'the status moved' 'SUSPENDED' \
  "$(psqlq "SELECT status FROM hbh.users WHERE user_id=${NEW_USER:-0}")"
eq admin 'an unknown status is refused' '400' \
  "$(req PATCH "/api/v1/users/${NEW_USER:-0}" '{"status":"HAPPY"}' "$ADMIN")"
# The username is not editable at all: changing it orphans every audit
# row that names it.
eq admin 'the username cannot be changed' '400' \
  "$(req PATCH "/api/v1/users/${NEW_USER:-0}" '{"username":"renamed"}' "$ADMIN")"
eq admin 'and it did not move' 'a7_new' \
  "$(psqlq "SELECT username FROM hbh.users WHERE user_id=${NEW_USER:-0}")"

eq admin 'an account may not archive itself' '409' \
  "$(req DELETE "/api/v1/users/${ADMIN_ID:-0}" '' "$ADMIN")"
eq admin 'and says why' 'NOT_YOURSELF' "$(jstr "$BODY" code)"
eq admin 'the administrator is still here' 't' \
  "$(psqlq "SELECT active_flg FROM hbh.users WHERE user_id=${ADMIN_ID:-0}")"

eq admin 'another account can be archived' '204' \
  "$(req DELETE "/api/v1/users/${NEW_USER:-0}" '' "$ADMIN")"
eq admin 'archived, not deleted' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.users WHERE user_id=${NEW_USER:-0} AND NOT active_flg")"
eq admin 'and it can be restored' '204' \
  "$(req DELETE "/api/v1/users/${NEW_USER:-0}?restore=true" '' "$ADMIN")"
eq admin 'back on the list' 't' \
  "$(psqlq "SELECT active_flg FROM hbh.users WHERE user_id=${NEW_USER:-0}")"

# The identity tables stay closed to direct writing. Every route in is a
# function, so there is no second path that skips the centre check, the
# self-grant rule or the stamp.
eq admin 'no write grant on any identity table' '0' \
  "$(psqlq "SELECT count(*) FROM information_schema.role_table_grants WHERE grantee='hbh_app' AND table_schema='hbh' AND table_name IN ('users','roles','permissions','role_permissions','user_roles') AND privilege_type IN ('INSERT','UPDATE','DELETE')")"
eq admin 'and an anonymous connection reads no user' '0' \
  "$(psqlapp "SELECT count(*) FROM hbh.users")"

# =====================================================================
# CLEANUP - a recorded check like any other
# =====================================================================
OUT="$(psqlf "$ROOT/tests/fixtures/a7_teardown.sql")"
RC=$?
if [ "$RC" != "0" ]; then chk cleanup 'fixture removed' 1 "$OUT"; else chk cleanup 'fixture removed' 0; fi
eq cleanup 'no profile row survived' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.therapist_certificates c JOIN hbh.therapists t ON t.therapist_id=c.therapist_id JOIN hbh.users u ON u.user_id=t.user_id WHERE u.username LIKE 'a7\\_%'")"

verdict 'API PHASE 7'
