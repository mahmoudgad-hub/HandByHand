#!/usr/bin/env bash
# =====================================================================
# Hand By Hand (new) - Angular driver
#
# Nothing is installed on the host. Node lives in the web containers and
# every command below reaches it through docker.
#
#   bash scripts/web.sh test          all three projects
#   bash scripts/web.sh test portal   one of portal | ops | shared
#   bash scripts/web.sh build         production build of both apps
#
# WHY THIS EXISTS AND npm test DOES NOT DO
#
#   A RUN THAT RUNS NOTHING MUST FAIL. `ng test ops` reports
#
#       Executed 0 of 0 SUCCESS
#       TOTAL: 0 SUCCESS
#
#   and exits 0, because the operations console has no .spec.ts file in
#   it at all. karma.conf.cjs asks for failOnEmptyTestSuite and the
#   @angular/build:karma builder does not honour it - measured, not
#   assumed. So the guard is here, where it can actually refuse.
#
#   That zero is how the console went without a single unit test for as
#   long as it has existed while `npm test` said "passed". It is the
#   same shape as three other tools this week: a stamping script that
#   matched no file and exited 0, a grep that answered a question nobody
#   asked, and a browser that would not start as root while the command
#   returned success. THE TOOL ANSWERS WHAT IT WAS ASKED. The check has
#   to be that something happened, not that nothing complained.
#
#   It also runs INSIDE the container: node_modules is a Linux build in
#   a named volume, and reaching it from the host finds an esbuild
#   binary for the wrong platform.
# =====================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINER="hbh-web-portal"
PROJECTS=(portal ops shared)

# Where each project's specs live, for the count that must not be zero.
spec_dir() {
  case "$1" in
    portal) echo "web/portal/src" ;;
    ops)    echo "web/ops/src" ;;
    shared) echo "web/shared/src" ;;
    *)      echo "" ;;
  esac
}

run_one() {
  local project="$1"
  local dir
  dir="$(spec_dir "$project")"
  if [ -z "$dir" ]; then
    echo "unknown project: $project" >&2
    return 1
  fi

  # Counted on the HOST, before the container is asked to do anything:
  # the point is to refuse the run, not to interpret its output.
  local count
  count="$(find "$ROOT/$dir" -name '*.spec.ts' -type f 2>/dev/null | wc -l | tr -d ' ')"
  echo "--- $project: $count spec file(s)"
  if [ "$count" -eq 0 ]; then
    echo "" >&2
    echo "REFUSED: $project has no .spec.ts file." >&2
    echo "A suite that runs nothing is not a suite that passed - and" >&2
    echo "'ng test $project' would have printed 'TOTAL: 0 SUCCESS' and" >&2
    echo "exited 0. Write one spec, or say out loud that this project" >&2
    echo "is untested; do not let a green line say it for you." >&2
    return 1
  fi

  docker exec "$CONTAINER" sh -c \
    "cd /app && CHROME_BIN=/usr/bin/chromium npx ng test $project --watch=false"
  local rc=$?
  if [ "$rc" != "0" ]; then
    echo "$project: FAILED (exit $rc)" >&2
    return 1
  fi
  echo "$project: passed"
  return 0
}

cmd_test() {
  local wanted="${1:-}"
  local failed=0
  if [ -n "$wanted" ]; then
    run_one "$wanted" || failed=1
  else
    for project in "${PROJECTS[@]}"; do
      run_one "$project" || failed=1
    done
  fi
  echo ""
  if [ "$failed" != "0" ]; then
    echo "WEB TESTS NOT ACCEPTED"
    return 1
  fi
  echo "WEB TESTS ACCEPTED"
  return 0
}

cmd_build() {
  local failed=0
  docker exec "$CONTAINER" sh -c "cd /app && npx ng build portal --configuration production" || failed=1
  docker exec hbh-web-ops sh -c "cd /app && npx ng build ops --configuration production" || failed=1
  [ "$failed" = "0" ] || return 1
  return 0
}

case "${1:-}" in
  test)  cmd_test "${2:-}" ;;
  build) cmd_build ;;
  *)     sed -n '3,12p' "${BASH_SOURCE[0]}" ; exit 2 ;;
esac
