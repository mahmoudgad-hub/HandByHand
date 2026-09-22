#!/usr/bin/env bash
# X4 PREFLIGHT - can the path from zero be walked at all today?
#
#   DEV_STAFF_PASSWORD='...' bash tests/test-cases/run/x4_preflight.sh
#
# This file WRITES NOTHING. It answers the questions that decide whether
# the walk in 15-zero-to-session.md would measure the product or measure
# a missing prerequisite:
#
#   1. the ground it would be measured on (image id + migration ledger),
#   2. the operator accounts and THE PERMISSIONS THEY USE, by name,
#   3. the seeded catalogue a booking needs,
#   4. and whether every route on the path is registered.
#
# WHY A 401 IS THE ANSWER IT LOOKS FOR. An unregistered path answers 404,
# and a registered one behind requireAuth answers 401 to a call with no
# token. So 401 proves the route EXISTS. It does not prove it works -
# that is what the walk itself is for, and the difference is written here
# so nobody reads this file's green as the card being done.
#
# A MISSING PIECE IS A FAILURE, NOT A SKIP. The whole reason HBH-015
# exists is that the once-per-child steps were never walked; a preflight
# that shrugged at a missing route would reproduce exactly that.
set -uo pipefail
cd "$(dirname "$0")/../../.."
. tests/api/lib.sh

echo '=============== X4 preflight - the path from zero ==============='
echo "base: $API_BASE"

# --- 1. the ground -------------------------------------------------------
IMAGE="$(docker inspect hbh-api --format '{{.Image}}' 2>/dev/null | cut -c8-19)"
LEDGER="$(psqlq "SELECT count(*) || '|' || max(version) FROM hbh.schema_migrations")"
printf '\nground: image %s  ·  ledger %s\n\n' "${IMAGE:-?}" "${LEDGER:-?}"
chk ground 'the api image id is readable'     "$([ -n "$IMAGE" ] && echo 0 || echo 1)" 'docker inspect returned nothing'
chk ground 'the migration ledger is readable' "$([ -n "$LEDGER" ] && echo 0 || echo 1)" 'psql returned nothing'
eq  ground 'the service answers /healthz' '200' "$(req GET /healthz)"

# --- 2. the operators, and the rights the path actually uses -------------
# Named one by one. "Three staff accounts exist" would stay green the day
# somebody narrows RECEPTION, and every refusal after it would then prove
# a permission gap rather than the rule under test.
for u in dev_reception dev_admin dev_therapist; do
  eq operators "account $u is seeded and can sign in" '1' \
     "$(psqlq "SELECT count(*) FROM hbh.users WHERE username='$u' AND active_flg AND status='ACTIVE' AND password_hash IS NOT NULL")"
done

perm_of() { # perm_of <username> <permission code> -> 1 or 0
  psqlq "SELECT count(*) FROM hbh.users u
           JOIN hbh.user_roles ur       ON ur.user_id = u.user_id
           JOIN hbh.role_permissions rp ON rp.role_id = ur.role_id
           JOIN hbh.permissions p       ON p.permission_id = rp.permission_id
          WHERE u.username = '$1' AND p.code = '$2'"
}
# Each right is the one its STEP asks for, read out of the function that
# asks: hbh.convert_enrolment wants ENROLMENT.MANAGE, hbh.grant_portal_access
# wants GUARDIAN.MANAGE, hbh.assign_therapist wants STAFF.MANAGE. The first
# draft of this file asserted CHILD.MANAGE on reception and went red on a
# right no step on this path uses - a guess, where the source was one query
# away.
#
# And the division is not decoration: reception does NOT hold STAFF.MANAGE,
# so the walk has to put the admin on the caseload step. A suite that signed
# everything in as one account would never learn that.
eq operators 'reception holds ENROLMENT.MANAGE (convert)'      '1' "$(perm_of dev_reception 'ENROLMENT.MANAGE')"
eq operators 'reception holds GUARDIAN.MANAGE (portal access)' '1' "$(perm_of dev_reception 'GUARDIAN.MANAGE')"
eq operators 'reception holds APPOINTMENT.BOOK'                '1' "$(perm_of dev_reception 'APPOINTMENT.BOOK')"
eq operators 'reception does NOT hold STAFF.MANAGE'            '0' "$(perm_of dev_reception 'STAFF.MANAGE')"
eq operators 'admin holds STAFF.MANAGE (caseload)'             '1' "$(perm_of dev_admin 'STAFF.MANAGE')"
eq operators 'therapist holds SESSION.START'                   '1' "$(perm_of dev_therapist 'SESSION.START')"
eq operators 'therapist holds SESSION.COMPLETE'                '1' "$(perm_of dev_therapist 'SESSION.COMPLETE')"
eq operators 'therapist holds NOTE.PUBLISH'                    '1' "$(perm_of dev_therapist 'NOTE.PUBLISH')"

# The password is not in the repository and has no default: db/dev/
# staff_accounts.sql refuses to run without DEV_STAFF_PASSWORD. So the
# walk cannot sign anybody in unless this session was given it too.
STAFF_PW="${X4_STAFF_PASSWORD:-${DEV_STAFF_PASSWORD:-}}"
if [ -z "$STAFF_PW" ]; then
  chk operators 'the dev staff password is available to this run' 1 \
      'set DEV_STAFF_PASSWORD (or X4_STAFF_PASSWORD) - the walk signs in as reception, and no password means no walk'
else
  TOKEN="$(staff_login dev_reception "$STAFF_PW")"
  chk operators 'reception can actually sign in with it' \
      "$([ -n "$TOKEN" ] && echo 0 || echo 1)" 'staff login returned no token'
fi

# --- 3. the catalogue a booking needs ------------------------------------
# Seeded, not made here. Its absence is a stop: a walk on an empty
# catalogue is refused by a business rule twenty checks later and reads
# as a defect in the route under test.
chk catalogue 'a service that opens a session exists' \
    "$([ "$(psqlq "SELECT count(*) FROM hbh.services WHERE active_flg AND creates_session_flg")" -gt 0 ] && echo 0 || echo 1)" \
    'no service with creates_session_flg'
chk catalogue 'a room exists' \
    "$([ "$(psqlq "SELECT count(*) FROM hbh.rooms WHERE active_flg")" -gt 0 ] && echo 0 || echo 1)" 'no active room'
chk catalogue 'a therapist has working hours' \
    "$([ "$(psqlq "SELECT count(*) FROM hbh.therapist_working_hours WHERE active_flg")" -gt 0 ] && echo 0 || echo 1)" \
    'no working hours - every slot would be outside them'
chk catalogue 'a therapist is linked to a service' \
    "$([ "$(psqlq "SELECT count(*) FROM hbh.therapist_services WHERE active_flg")" -gt 0 ] && echo 0 || echo 1)" \
    'no therapist_services row - booking is refused before the rule under test'
for s in CHILD APPT ENROL; do
  eq catalogue "the $s number series is defined" '1' \
     "$(psqlq "SELECT count(*) FROM hbh.number_series WHERE code='$s' AND active_flg")"
done

# --- 4. the functions the once-per-child steps stand on ------------------
# Read from pg_proc BY NAME. A route can be live over a function that was
# never applied - the API descends first, and the schema waits.
for f in grant_portal_access assign_therapist convert_enrolment submit_enrolment; do
  eq schema "hbh.$f exists" '1' \
     "$(psqlq "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='hbh' AND p.proname='$f'")"
done

# --- 5. every route on the path is registered ----------------------------
# 401 = registered and guarded. 404 = not there. Anything else is worth
# reading before the walk starts.
route_is_live() { # route_is_live <method> <path> -> 0 when 401
  local code; code="$(req "$1" "$2" '{}')"
  if [ "$code" = '401' ]; then echo 0; else echo "1"; fi
}
chk routes 'POST /guardians/{id}/portal-access is registered  (HBH-011)' \
    "$(route_is_live POST /api/v1/guardians/1/portal-access)" 'expected 401 from an unauthenticated call'
chk routes 'POST /children/{id}/caseload is registered        (HBH-013)' \
    "$(route_is_live POST /api/v1/children/1/caseload)" 'expected 401'
chk routes 'PATCH /enrolments/{id} is registered' \
    "$(route_is_live PATCH /api/v1/enrolments/1)" 'expected 401'
chk routes 'POST /enrolments/{id}/convert is registered' \
    "$(route_is_live POST /api/v1/enrolments/1/convert)" 'expected 401'
chk routes 'POST /appointments is registered' \
    "$(route_is_live POST /api/v1/appointments)" 'expected 401'
chk routes 'POST /appointments/{id}/session is registered' \
    "$(route_is_live POST /api/v1/appointments/1/session)" 'expected 401'
chk routes 'PATCH /sessions/{id}/close is registered' \
    "$(route_is_live PATCH /api/v1/sessions/1/close)" 'expected 401'
chk routes 'POST /notes/{id}/publish is registered' \
    "$(route_is_live POST /api/v1/notes/1/publish)" 'expected 401'
chk routes 'POST /plans is registered' \
    "$(route_is_live POST /api/v1/plans)" 'expected 401'

# The one door that must NOT ask for a token, because the whole path
# starts at a stranger with no account.
eq routes 'POST /enrolments answers a stranger (not 401)' 'open' \
   "$(c="$(req POST /api/v1/enrolments '{}')"; [ "$c" = '401' ] && echo "guarded($c)" || echo open)"

# --- 6. and the ground did not move while we read it ---------------------
LEDGER2="$(psqlq "SELECT count(*) || '|' || max(version) FROM hbh.schema_migrations")"
IMAGE2="$(docker inspect hbh-api --format '{{.Image}}' 2>/dev/null | cut -c8-19)"
eq ground 'the ledger is the same at the end' "$LEDGER" "$LEDGER2"
eq ground 'the image is the same at the end'  "$IMAGE"  "$IMAGE2"
printf '\nground: image %s  ·  ledger %s\n' "${IMAGE2:-?}" "${LEDGER2:-?}"

verdict 'X4 PREFLIGHT'
