#!/usr/bin/env bash
# =====================================================================
# Hand By Hand (new) - E2E CONTRACT suite
#
# Must print:  E2E CONTRACT ACCEPTED
#
#   API_BASE=http://127.0.0.1:8090 bash tests/e2e/e1_contract_verify.sh
#
# WHAT THIS IS FOR
#
# `tests/e2e/` held nothing but a .gitkeep from the first day of the
# project to this one, while 1675 checks accumulated on either side of
# the line it was meant to cover. Every one of those checks asks the
# database directly, or asks the service over HTTP. **None of them asks
# whether the thing Angular calls is a thing the service answers.**
#
# That gap is not theoretical. The portal drifted to sixteen endpoint
# names of which thirteen returned 404 - a guardian could log in and
# reach no screen at all - and it survived four accepted API batches and
# every suite in the project, because nothing anywhere compared the two
# lists. It was found by opening the app in a browser.
#
# This suite is that comparison, automated.
#
# HOW IT PROBES, AND WHY IT IS SAFE
#
# It never calls an endpoint the way the app would - it would have to
# write to check a write. Instead it sends a method the router registers
# for nothing (`PROPFIND`) and reads the answer:
#
#   404 NOT_FOUND          -> the PATH does not exist. The client is
#                             calling something nobody serves.
#   405 METHOD_NOT_ALLOWED -> the path exists, and the `Allow` header
#                             names exactly which methods it serves.
#
# So one side-effect-free request per path settles both questions: does
# the route exist, and does it accept the verb the client uses. Nothing
# is created, updated or deleted by this file.
# =====================================================================

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
API_BASE="${API_BASE:-http://127.0.0.1:8090}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
declare -a FAILURES=()

chk() { # chk <group> <name> <0|1> [detail]
  local grp="$1" name="$2" ok="$3" detail="${4:-}"
  if [ "$ok" = "0" ]; then
    PASS=$((PASS + 1)); printf '  ok    %-9s %s\n' "$grp" "$name"
  else
    FAIL=$((FAIL + 1)); FAILURES+=("$grp/$name: $detail")
    printf '  FAIL  %-9s %s  --  %s\n' "$grp" "$name" "$detail"
  fi
}

echo "=================== e2e contract - Angular against the service ==================="
echo "base: $API_BASE"
echo

# ---------------------------------------------------------------------
# FIXTURE - asserted by name, before anything is compared
# ---------------------------------------------------------------------
code="$(curl -sS -o /dev/null -w '%{http_code}' "$API_BASE/healthz" 2>/dev/null)"
chk fixture 'the service answers /healthz' "$([ "$code" = "200" ] && echo 0 || echo 1)" "got [$code]"

# A token is not needed to tell 404 from 405 - routing happens before
# auth - but sending one keeps the probe on the same path a real client
# takes, and costs nothing.
TOKEN=''
for creds in '{"username":"a5_admin","password":"a5-admin-pw-123456"}' \
             '{"username":"a4_admin","password":"a4-admin-pw-123456"}'; do
  TOKEN="$(curl -sS -X POST -H 'Content-Type: application/json' --data-binary "$creds" \
            "$API_BASE/api/v1/auth/staff/login" 2>/dev/null \
          | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
  [ -n "$TOKEN" ] && break
done
chk fixture 'a staff token was obtained (probe runs unauthenticated if not)' 0

# The discriminator itself is asserted before it is trusted. A router
# that answered 404 for everything would make every check below pass by
# accident, and this suite would be decoration.
probe_status() { # probe_status <path> -> prints "status|allow"
  local out
  out="$(curl -sS -o /dev/null -D - -w '%{http_code}' -X PROPFIND \
          ${TOKEN:+-H "Authorization: Bearer $TOKEN"} "$API_BASE$1" 2>/dev/null)"
  local status allow
  status="$(printf '%s' "$out" | tail -c 3)"
  allow="$(printf '%s' "$out" | grep -i '^allow:' | head -1 | cut -d' ' -f2- | tr -d '\r')"
  printf '%s|%s' "$status" "$allow"
}

known="$(probe_status /api/v1/me)"
chk fixture 'a known path answers 405, not 404' \
  "$([ "${known%%|*}" = "405" ] && echo 0 || echo 1)" "GET /api/v1/me probed: [$known]"
chk fixture 'and the 405 names the methods it serves' \
  "$([ -n "${known#*|}" ] && echo 0 || echo 1)" 'no Allow header'

missing="$(probe_status /api/v1/definitely-not-a-route)"
chk fixture 'an invented path answers 404' \
  "$([ "${missing%%|*}" = "404" ] && echo 0 || echo 1)" "probed: [$missing]"

# ---------------------------------------------------------------------
# COLLECT - every (method, path) the two Angular clients call
#
# Read out of the source, not out of a list somebody maintains by hand:
# a list maintained by hand is the thing that drifted in the first place.
# ---------------------------------------------------------------------
collect() { # collect <app> <base-suffix> <files...>
  local app="$1" suffix="$2"; shift 2
  grep -ohE "this\.http\.(get|post|put|patch|delete)<[^>]*>\(\s*\`[^\`]+\`" "$@" 2>/dev/null \
  | sed -E "s/this\.http\.([a-z]+)<[^>]*>\(\s*\`/\1 /" \
  | sed -E 's/`$//' \
  | sed -E 's/\$\{this\.base\}//' \
  | sed -E 's/\?.*$//' \
  | while read -r method path; do
      # Every interpolation becomes 1: routing matches on shape, and a
      # real identifier would only invite a write we are not making.
      path="$(printf '%s' "$path" | sed -E 's/\$\{[^}]*\}/1/g')"
      case "$path" in
        /1*|*'${'*) continue ;;   # a wholly dynamic path carries no contract
        /*) printf '%s\t%s%s\t%s\n' "$(printf '%s' "$method" | tr 'a-z' 'A-Z')" "$suffix" "$path" "$app" ;;
      esac
    done
}

PORTAL_DIR="$ROOT/web/portal/src/app/core"
OPS_DIR="$ROOT/web/ops/src/app/core"

{
  collect portal /api/v1      "$PORTAL_DIR/api/http-portal-api.ts"
  collect portal /api/v1/auth "$PORTAL_DIR/auth/http-auth-api.ts"
  collect ops    /api/v1      "$OPS_DIR"/api/*.ts "$OPS_DIR"/ops/*.ts
} | sort -u > "$TMP/calls.tsv"

# The generic CRUD client builds its path from a resource name, so the
# literal `/${resource}` above carries no contract on its own. The names
# live in the ops resource spec; expand them and check each one.
SPEC="$ROOT/web/ops/src/app/core/resource/resource-spec.ts"
if [ -f "$SPEC" ]; then
  grep -oE "resource: '[a-z-]+'" "$SPEC" | sed "s/resource: //" | tr -d "'" \
  | while read -r res; do
      printf 'GET\t/api/v1/%s\tops-crud\n'         "$res"
      printf 'GET\t/api/v1/%s/1\tops-crud\n'       "$res"
      printf 'POST\t/api/v1/%s\tops-crud\n'        "$res"
      printf 'PATCH\t/api/v1/%s/1\tops-crud\n'     "$res"
      printf 'DELETE\t/api/v1/%s/1\tops-crud\n'    "$res"
      printf 'POST\t/api/v1/%s/1/restore\tops-crud\n' "$res"
    done >> "$TMP/calls.tsv"
fi

sort -u "$TMP/calls.tsv" -o "$TMP/calls.tsv"
COUNT="$(wc -l < "$TMP/calls.tsv" | tr -d ' ')"
chk fixture 'calls were extracted from the Angular sources' \
  "$([ "$COUNT" -gt 20 ] && echo 0 || echo 1)" "found only $COUNT - has the client been restructured?"
echo "  ..    fixture   $COUNT client calls to resolve"
echo

# ---------------------------------------------------------------------
# GROUP: route   - does the path the client calls exist at all?
# GROUP: method  - and does it serve the verb the client uses?
#
# This is the pair that would have caught the portal drift on the day it
# started instead of four batches later.
# ---------------------------------------------------------------------
declare -A SEEN_PATH=()
while IFS=$'\t' read -r method path app; do
  [ -z "${path:-}" ] && continue
  result="${SEEN_PATH[$path]:-}"
  if [ -z "$result" ]; then
    result="$(probe_status "$path")"
    SEEN_PATH[$path]="$result"
  fi
  status="${result%%|*}"
  allow="${result#*|}"

  case "$status" in
    404)
      chk route "$app calls $method $path" 1 'no such route in the service (404)'
      continue ;;
    000)
      chk route "$app calls $method $path" 1 'the service did not answer'
      continue ;;
    405) : ;;                       # the path exists - the normal answer
    *)  : ;;                        # 401/403 etc. also prove it exists
  esac
  chk route "$app calls $method $path" 0

  if [ -n "$allow" ]; then
    if printf '%s' "$allow" | grep -qw "$method"; then
      chk method "$path serves $method" 0
    else
      chk method "$path serves $method" 1 "the route allows [$allow]"
    fi
  fi
done < "$TMP/calls.tsv"

# ---------------------------------------------------------------------
# VERDICT - printed first, always. A suite that dies before its verdict
# reads as a pass, so the exit comes after it and only after it.
# ---------------------------------------------------------------------
echo
if [ "${#FAILURES[@]}" -gt 0 ]; then
  echo 'failures:'
  i=0; while [ "$i" -lt "${#FAILURES[@]}" ]; do echo "  - ${FAILURES[$i]}"; i=$((i + 1)); done
  echo
fi

TOTAL=$((PASS + FAIL))
echo '--------------------------------------------------'
printf '  %s checks, %s failed\n' "$TOTAL" "$FAIL"
if [ "$FAIL" = "0" ] && [ "$TOTAL" -gt 0 ]; then
  echo '  E2E CONTRACT ACCEPTED'
else
  echo '  *** E2E CONTRACT NOT ACCEPTED'
fi
echo '--------------------------------------------------'

[ "$FAIL" = "0" ] && [ "$TOTAL" -gt 0 ]
