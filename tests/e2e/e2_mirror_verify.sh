#!/usr/bin/env bash
# =====================================================================
# Hand By Hand (new) - E2E MIRROR suite
#
# Must print:  E2 ACCEPTED
#
#   API_BASE=http://127.0.0.1:8090 bash tests/e2e/e2_mirror_verify.sh
#
# ONE QUESTION, ASKED TWENTY-SEVEN TIMES:
#
#   For every feature a family uses in the portal, is there a counterpart
#   on the staff side - and can a member of staff actually REACH it?
#
# Why this is not covered anywhere else. The database suites prove each
# table's rules. The API suites prove each endpoint answers. e1 proves
# every path a client calls is a path the service serves. None of them
# asks whether the two apps make a PAIR: a parent logs a home activity
# and nobody at the centre can see that they did; a parent answers a
# satisfaction survey and no screen shows the result; a clinician writes
# a note "for the family" and no action exists to send it.
#
# Each of those is invisible to every layer's own tests, because each
# layer is individually correct. The defect lives in the space between.
#
# TWO PROBES PER PAIR, and both must pass:
#
#   route  - does the service serve the counterpart path at all?
#            Asked with a method the router registers for nothing, so
#            405 means "path exists, wrong verb" and 404 means "no such
#            path". Nothing is written; see e1 for the full reasoning.
#   wired  - does the staff app actually CALL it?
#            An endpoint nobody calls is a mirror with no glass in it.
#            This is the probe that catches the two live gaps, and it
#            reads the app's source rather than a hand-kept list -
#            a hand-kept list is what drifted in the first place.
#
# It obeys the five rules in tests/api/lib.sh: the verdict always
# prints, a negative names what it expected, the fixture is asserted
# before the tests, and cleanup is a recorded check - there is nothing
# to clean up here because this suite writes nothing at all.
# =====================================================================

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
API_BASE="${API_BASE:-http://127.0.0.1:8090}"
PORTAL_SRC="$ROOT/web/portal/src/app"
OPS_SRC="$ROOT/web/ops/src/app"

PASS=0
FAIL=0
declare -a FAILURES=()

chk() { # chk <group> <name> <0|1> [detail]
  local grp="$1" name="$2" ok="$3" detail="${4:-}"
  if [ "$ok" = "0" ]; then
    PASS=$((PASS + 1)); printf '  ok    %-7s %s\n' "$grp" "$name"
  else
    FAIL=$((FAIL + 1)); FAILURES+=("$grp/$name: $detail")
    printf '  FAIL  %-7s %s  --  %s\n' "$grp" "$name" "$detail"
  fi
}

# probe_route <path> -> prints the status for an unregistered method.
# 405 = the path exists. 404 = it does not. Nothing is written either way.
probe_route() {
  curl -sS -o /dev/null -w '%{http_code}' -X PROPFIND "$API_BASE$1" 2>/dev/null || echo 000
}

# calls <src-dir> <needle> -> 0 when the app's own source calls it.
calls() {
  grep -rqF "$2" "$1" --include=*.ts --include=*.html 2>/dev/null
}

echo "=================== E2 - portal / ops mirror ==================="
echo "service: $API_BASE"
echo "portal:  ${PORTAL_SRC#$ROOT/}"
echo "ops:     ${OPS_SRC#$ROOT/}"
echo

# =====================================================================
# FIXTURE - the tools before the tests
#
# A router that answered 405 for everything would make every route probe
# below pass by accident, and a grep that matched everything would make
# every wiring probe pass the same way. Both are proved wrong first.
# =====================================================================
eq_status() { if [ "$2" = "$3" ]; then chk "$1" "$4" 0; else chk "$1" "$4" 1 "expected [$3], got [$2]"; fi; }

eq_status fixture "$(curl -sS -o /dev/null -w '%{http_code}' "$API_BASE/healthz" 2>/dev/null)" '200' \
  'the service is up'
eq_status fixture "$(probe_route /api/v1/me)" '405' \
  'a known path answers 405 to an unregistered method'
eq_status fixture "$(probe_route /api/v1/no-such-path-here)" '404' \
  'an invented path answers 404'

chk fixture 'the portal source is readable' \
  "$([ -d "$PORTAL_SRC" ] && echo 0 || echo 1)" "missing $PORTAL_SRC"
chk fixture 'the ops source is readable' \
  "$([ -d "$OPS_SRC" ] && echo 0 || echo 1)" "missing $OPS_SRC"
chk fixture 'the wiring probe can tell present from absent' \
  "$(calls "$OPS_SRC" '/auth/staff/login' && ! calls "$OPS_SRC" 'zzz-not-a-real-endpoint' && echo 0 || echo 1)" \
  'the grep matched everything or nothing - it proves nothing'
echo

# =====================================================================
# THE PAIRS
#
# pair <id> <what the family does> <staff counterpart path> <needle the
#      staff app must contain>
#
# The needle is a fragment of the path as the app writes it, because the
# app builds URLs from template literals and the full path never appears
# as one string in the source.
# =====================================================================
pair() {
  local id="$1" what="$2" path="$3" needle="$4"
  local st; st="$(probe_route "$path")"
  case "$st" in
    405|200|201|204|400|401|403|409|422) chk route "$id $what -> $path" 0 ;;
    404) chk route "$id $what -> $path" 1 "the service serves no such path (404)" ;;
    *)   chk route "$id $what -> $path" 1 "unexpected [$st]" ;;
  esac
  if calls "$OPS_SRC" "$needle"; then
    chk wired "$id the centre can reach it" 0
  else
    chk wired "$id the centre can reach it" 1 "no screen in web/ops calls [$needle]"
  fi
}

# ---- identity --------------------------------------------------------
pair M-01 'family signs in'            /api/v1/auth/staff/login          '/auth/staff/login'
pair M-02 'family signs out'           /api/v1/auth/logout               '/auth/logout'

# ---- the child -------------------------------------------------------
pair M-03 'sees their children'        /api/v1/children                  '/children'
pair M-04 "opens a child's file"       /api/v1/children/1                'children/'
pair M-05 "the child's guardians"      /api/v1/children/1/guardians      '/guardians'

# ---- the diary -------------------------------------------------------
pair M-06 'reads appointments'         /api/v1/appointments              '/appointments'
pair M-07 'a slot is booked'           /api/v1/appointments/validate     '/appointments/validate'
pair M-08 'an appointment moves'       /api/v1/appointments/1/status     '/status'
pair M-09 'reads sessions'             /api/v1/appointments/1/session    '/session'
pair M-10 'a session is closed'        /api/v1/sessions/1/close          '/sessions/'

# ---- the clinical record --------------------------------------------
pair M-11 'reads plans'                /api/v1/plans                     "'plans'"
pair M-12 'reads goals'                /api/v1/goals                     "'goals'"
pair M-13 'a note is written'          /api/v1/sessions/1/note           '/note'
pair M-14 'reads reports'              /api/v1/reports                   '/reports'
pair M-15 'a report is published'      /api/v1/reports/1/publish         '/publish'

# ---- the home programme ---------------------------------------------
pair M-16 'reads home activities'      /api/v1/child-activities          "'child-activities'"
pair M-17 'LOGS one done at home'      /api/v1/children/1/activity-log   'activity-log'

# ---- money -----------------------------------------------------------
pair M-18 'reads invoices'             /api/v1/invoices                  '/invoices'
pair M-19 'an invoice is issued'       /api/v1/invoices/1/issue          '/issue'
pair M-20 'a payment is recorded'      /api/v1/invoices/1/payments       '/payments'
pair M-21 'reads packages'             /api/v1/children/1/packages       '/packages'

# ---- asking for something -------------------------------------------
pair M-22 'submits a request'          /api/v1/requests                  '/requests'
pair M-23 'the request is decided'     /api/v1/requests/1                'requests/'

# ---- coming in from outside -----------------------------------------
pair M-24 'applies to the centre'      /api/v1/enrolments                '/enrolments'
pair M-25 'the application converts'   /api/v1/enrolments/1/convert      '/convert'

# ---- the therapist the family reads about ---------------------------
pair M-26 "reads a therapist's page"   /api/v1/therapists/1/profile      '/profile'
pair M-27 'the page is published'      /api/v1/therapists/1/publish      '/publish'

echo

# =====================================================================
# THE PAIRS WITH NO OTHER HALF
#
# Stated as their own checks rather than folded into the table above,
# because each is a decision somebody has to take - not a typo.
# =====================================================================

# A note is born INTERNAL and reaches the family only when published.
# The function exists, the permission exists, the family's read endpoint
# exists. The act in the middle does not.
NOTE_PUBLISH="$(probe_route /api/v1/notes/1/publish)"
if [ "$NOTE_PUBLISH" = "404" ]; then
  chk mirror 'M-28 a note written for the family can be sent to them' 1 \
    'no publish route for a session note - the family can never receive one'
else
  chk mirror 'M-28 a note written for the family can be sent to them' 0
fi

# The database refuses to set can_view_live_flg without a recorded
# LIVE_VIEW consent (migration 0015). Nothing above the database can
# record one.
GUARDIAN_CONSENT=1
for p in /api/v1/guardians/1/consent /api/v1/consents /api/v1/children/1/consents; do
  st="$(probe_route "$p")"
  [ "$st" != "404" ] && GUARDIAN_CONSENT=0
done
chk mirror 'M-29 a guardian consent can be recorded by the centre' "$GUARDIAN_CONSENT" \
  'the schema requires a LIVE_VIEW consent before live viewing, and no route records one'

# The family answers a satisfaction survey. Somebody has to read the
# answers. Asked for the RESULTS path specifically: the centre can already
# manage survey definitions through the 'nps-surveys' resource, and a
# looser needle matches that and calls the pair whole while the answers
# are still unread. It did exactly that on the first run of this file.
#
# Both halves are required. The app builds this URL as `${base}/summary` with
# base ending in /nps, so the whole path never appears as one string - looking
# for "/nps/summary" reported the screen missing while it sat there calling it.
# And looking only for "summary" would match half the codebase.
if calls "$OPS_SRC" 'api/v1/nps' && calls "$OPS_SRC" '/summary'; then
  chk mirror 'M-30 the centre can read the satisfaction survey answers' 0
else
  chk mirror 'M-30 the centre can read the satisfaction survey answers' 1 \
    'GET /api/v1/nps/summary is served but no screen in web/ops calls it'
fi

echo

# =====================================================================
# AND THE OTHER DIRECTION
#
# A mirror has two faces. These check that what the centre writes has
# somewhere to land in the portal - the cheaper direction, because the
# portal is a read surface and its gaps show up as an empty screen
# rather than as silence.
# =====================================================================
back() { # back <id> <what the centre does> <needle the portal must contain>
  if calls "$PORTAL_SRC" "$3"; then chk back "$1 $2" 0
  else chk back "$1 $2" 1 "nothing in web/portal reads [$3]"; fi
}

back B-01 'a published report reaches a screen'      '/reports'
back B-02 'an issued invoice reaches a screen'       '/invoices'
back B-03 'an assigned activity reaches a screen'    '/activities'
back B-04 'a decided request reaches a screen'       '/requests'
back B-05 'a booked appointment reaches a screen'    '/appointments'
back B-06 'a plan reaches a screen'                  '/plans'
back B-07 'a package reaches a screen'               '/packages'
back B-08 'a balance reaches a screen'               '/balance'
back B-09 'a live session reaches a screen'          '/stream'
back B-10 "a therapist's page reaches a screen"      '/therapists/'
back B-11 'a note reaches a screen'                  '/notes'

# =====================================================================
# VERDICT - printed first, always. The exit comes after it.
# =====================================================================
echo
if [ "${#FAILURES[@]}" -gt 0 ]; then
  echo 'failures:'
  i=0
  while [ "$i" -lt "${#FAILURES[@]}" ]; do echo "  - ${FAILURES[$i]}"; i=$((i + 1)); done
  echo
fi

TOTAL=$((PASS + FAIL))
echo '--------------------------------------------------'
printf '  %s checks, %s failed\n' "$TOTAL" "$FAIL"
if [ "$FAIL" = "0" ] && [ "$TOTAL" -gt 0 ]; then
  echo '  E2 ACCEPTED'
else
  echo '  *** E2 NOT ACCEPTED'
fi
echo '--------------------------------------------------'

[ "$FAIL" = "0" ] && [ "$TOTAL" -gt 0 ] || exit 1
