#!/usr/bin/env bash
#
# The gate. One entry point, five stages, and a rule that outranks all of
# them: A STAGE THAT RAN NOTHING HAS FAILED.
#
# That rule is not a preference. It is written down because this project has
# been told "green" by four different things that did no work at all:
#
#   - `ng test` returned 0 three times while ChromeHeadless never started
#     ("running as root without --no-sandbox"). Zero specs executed, exit 0.
#   - A seed file's INSERT ... SELECT read an empty table, matched nothing,
#     inserted nothing, and reported success. Thirteen checks failed later
#     with no hint of why.
#   - A teardown deleted zero rows, because the pattern it used was not the
#     prefix the fixture had written. Deleting zero rows is a success.
#   - `check_no_docs` was written, passed on its first run, and only proved
#     it read anything when it was pointed at the live server and fell over
#     two files by name.
#
# So every stage here reports a COUNT OF WHAT IT EXECUTED, and the count is
# asserted before the exit code is believed. `--self-test` proves each of
# those counters rejects an empty transcript, because a counter that has
# never been seen refusing is itself untested.
#
# THREE THINGS THIS SCRIPT WILL NOT DO
#
#   1. It never calls `db.sh reset` or `db.sh nuke`. The database is shared
#      between concurrent sessions; a reset pulled the schema out from under
#      another process mid-migration once already. `migrate` only.
#   2. It never calls `npm test` or `ng test` directly. `scripts/web.sh test`
#      counts spec files on the host and REFUSES at zero. Calling the
#      underlying tool skips the only guard that exists. (karma's
#      `failOnEmptyTestSuite` does not cover this: @angular/build:karma
#      ignores it.)
#   3. It does not touch the deployed server unless asked. `surface` is
#      opt-in via HBH_CI_ORIGINS, because a probe with no origins configured
#      would pass by running nothing - the exact failure this file exists to
#      prevent.
#
# Usage:
#   bash deploy/ci/run.sh                 # every stage
#   bash deploy/ci/run.sh db api          # named stages
#   bash deploy/ci/run.sh --self-test     # prove the counters refuse zero
#   bash deploy/ci/run.sh --list
#
# Exit: 0 only when every requested stage ran work AND that work passed.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 1

# NOT under $ROOT. This project lives on a redirected Desktop that syncs to
# OneDrive, and a script that wrote its output into the tree once uploaded
# every database dump - the full clinical record of every child - to a
# personal cloud account. No error, no prompt, no log line. Transcripts here
# carry test output and failure detail, so they get the treatment the
# backups now get: the default lives outside the tree, and a configured
# path that lands in a sync folder STOPS the run rather than warning about
# it. A warning scrolls past; the discovery comes later, from somewhere
# nobody chose.
LOGDIR="${HBH_CI_LOGDIR:-$HOME/hbh-ci-logs}"

case "$LOGDIR" in
  "$ROOT"*|*OneDrive*|*Dropbox*|*"Google Drive"*|*iCloud*)
    echo "*** refusing to write CI logs to $LOGDIR" >&2
    echo "*** that path is inside the project tree or a sync folder." >&2
    echo "*** set HBH_CI_LOGDIR to somewhere that is neither." >&2
    exit 1 ;;
esac

mkdir -p "$LOGDIR" || { echo "cannot create $LOGDIR" >&2; exit 1; }

STAGES=(lint db api web surface)

PASSED=0
FAILED=0
declare -a RESULTS=()

# ---------------------------------------------------------------------------
# reporting
# ---------------------------------------------------------------------------

hr()   { printf '%s\n' "-----------------------------------------------------------"; }
info() { printf '  %s\n' "$*"; }
bad()  { printf '  *** %s\n' "$*" >&2; }

# record STAGE VERDICT DETAIL - the verdict line every stage ends on.
record() {
  local stage="$1" verdict="$2" detail="$3"
  RESULTS+=("$(printf '%-9s %-12s %s' "$stage" "$verdict" "$detail")")
  if [ "$verdict" = "PASS" ]; then PASSED=$((PASSED + 1)); else FAILED=$((FAILED + 1)); fi
}

# ---------------------------------------------------------------------------
# the counters
#
# Each takes a transcript on stdin and prints one integer: how much work the
# transcript proves was done. They are separate functions, and not inlined,
# for exactly one reason - so --self-test can feed each of them an empty
# string and watch it answer 0. A counter that cannot be run on its own
# cannot be shown to work.
# ---------------------------------------------------------------------------

# Every db suite ends on "N checks, M failed". Sum the N.
count_db_checks() {
  local n
  n="$(grep -oE '[0-9]+ checks, [0-9]+ failed' | grep -oE '^[0-9]+' | awk '{s+=$1} END {print s+0}')"
  printf '%s' "${n:-0}"
}

# ... and one "PHASE x ACCEPTED" per suite that reached its verdict.
count_db_verdicts() {
  grep -cE 'PHASE [0-9a-z]+ ACCEPTED' || true
}

# Go prints "ok <pkg>" per package that ran, and "no test files" for the
# rest. Only the first is work.
count_go_packages() {
  grep -cE '^(ok|--- PASS|PASS)' || true
}

# karma: "Executed 41 of 41". Sum the first number across projects. This is
# the assertion `web.sh` does NOT make - it counts spec FILES on the host,
# which is a different claim from "the browser ran them".
count_web_executed() {
  local n
  n="$(grep -oE 'Executed [0-9]+ of [0-9]+' | grep -oE '[0-9]+' | awk 'NR%2==1 {s+=$1} END {print s+0}')"
  printf '%s' "${n:-0}"
}

# surface: one line per probe this script wrote itself.
count_probes() {
  grep -cE '^\s*(OK|REFUSED) ' || true
}

# ---------------------------------------------------------------------------
# stages
#
# Shape of every one: run, capture, COUNT, then judge. The exit code is the
# last thing consulted and never the only thing.
# ---------------------------------------------------------------------------

stage_lint() {
  local log="$LOGDIR/lint.log" rc hits
  info "bash scripts/api.sh lint"
  bash scripts/api.sh lint >"$log" 2>&1; rc=$?

  # The lint guard's own history is why this stage counts. `cut -d: -f1` on
  # grep -rn output cut at the drive letter on a Windows path, so the check
  # reported every file as unguarded under a name of "C" - and stayed green
  # for weeks under Git Bash's /c/... paths. A lint run that emitted nothing
  # at all is the same class of silence.
  hits="$(wc -l <"$log" | tr -d ' ')"
  if [ "$hits" -eq 0 ]; then
    bad "lint printed nothing - it did not run, or it read no files"
    record lint "FAIL-EMPTY" "0 lines of output"
    return 1
  fi
  if [ "$rc" != 0 ]; then
    bad "lint refused - see $log"
    record lint "FAIL" "exit $rc"
    return 1
  fi
  record lint "PASS" "$hits lines"
  return 0
}

stage_db() {
  local log="$LOGDIR/db.log" rc checks verdicts suites
  suites="$(find "$ROOT/tests/db" -name 'p*_verify.sql' -type f | wc -l | tr -d ' ')"

  if [ "$suites" -eq 0 ]; then
    bad "no p*_verify.sql suites found - nothing to run"
    record db "FAIL-EMPTY" "0 suite files"
    return 1
  fi

  # Migrating is opt-in, not a side effect of typing the gate's name. The
  # database is shared with a running API, and "migrate only, never reset"
  # is not safe on its own: 0151 dropped a function the live API still
  # called, so a migrate ahead of the API build turns every report-draft
  # save into 42883. Schema and code do not move in one step, and a CI run
  # is not the place that decides which one moves first.
  if [ "${HBH_CI_MIGRATE:-0}" != "1" ]; then
    bad "db stage refused: it would run db.sh migrate on the shared database."
    bad "set HBH_CI_MIGRATE=1 only when a migrate is announced as safe."
    record db "FAIL-GATED" "migrate not authorised"
    return 1
  fi

  info "bash scripts/db.sh migrate"
  bash scripts/db.sh migrate >"$log" 2>&1; rc=$?
  if [ "$rc" != 0 ]; then
    bad "migrate refused - see $log"
    record db "FAIL" "migrate exit $rc"
    return 1
  fi

  # No argument. `cmd_verify` takes an optional phase name and, given one
  # that matches no file, runs zero suites and RETURNS 0 - a silent pass
  # that looks exactly like a real one. Passing nothing runs them all.
  info "bash scripts/db.sh verify   ($suites suites expected)"
  bash scripts/db.sh verify >>"$log" 2>&1; rc=$?

  checks="$(count_db_checks   <"$log")"
  verdicts="$(count_db_verdicts <"$log")"
  info "executed: $checks checks across $verdicts/$suites suites"

  if [ "$checks" -eq 0 ]; then
    bad "zero checks executed - the suites did not run"
    record db "FAIL-EMPTY" "0 checks"
    return 1
  fi
  if [ "$verdicts" -lt "$suites" ]; then
    bad "$((suites - verdicts)) suite(s) never reached a verdict"
    record db "FAIL" "$verdicts/$suites verdicts, $checks checks"
    return 1
  fi
  if [ "$rc" != 0 ]; then
    record db "FAIL" "$checks checks, refused"
    return 1
  fi
  record db "PASS" "$checks checks, $verdicts suites"
  return 0
}

stage_api() {
  local log="$LOGDIR/api.log" rc pkgs
  info "bash scripts/api.sh test"
  bash scripts/api.sh test >"$log" 2>&1; rc=$?

  pkgs="$(count_go_packages <"$log")"
  info "executed: $pkgs package result(s)"

  if [ "$pkgs" -eq 0 ]; then
    # "no test files" across the board is go's way of exiting 0 having
    # compiled and asserted nothing.
    bad "no Go package reported a result - nothing was tested"
    record api "FAIL-EMPTY" "0 packages"
    return 1
  fi
  if [ "$rc" != 0 ]; then
    record api "FAIL" "$pkgs packages, refused"
    return 1
  fi
  record api "PASS" "$pkgs packages"
  return 0
}

stage_web() {
  local log="$LOGDIR/web.log" rc executed
  # scripts/web.sh, never ng/npm - see note 2 in the header.
  info "bash scripts/web.sh test"
  bash scripts/web.sh test >"$log" 2>&1; rc=$?

  executed="$(count_web_executed <"$log")"
  info "executed: $executed spec(s) in the browser"

  if [ "$executed" -eq 0 ]; then
    bad "the browser executed zero specs"
    bad "this is the ChromeHeadless failure: ng exits 0 having run nothing."
    bad "web.sh counts spec FILES on the host, which is a different claim."
    record web "FAIL-EMPTY" "0 executed"
    return 1
  fi
  if [ "$rc" != 0 ]; then
    record web "FAIL" "$executed executed, refused"
    return 1
  fi
  record web "PASS" "$executed specs"
  return 0
}

stage_surface() {
  # Asks what must NOT be answered. `/` returning 200 proves nothing; a
  # published origin answering /api/v1/... proves everything, and did:
  # POST https://hbhskills.com/api/v1/auth/otp/request returned 200 with a
  # login code in the body for eleven minutes.
  local origins="${HBH_CI_ORIGINS:-}"
  if [ -z "$origins" ]; then
    bad "HBH_CI_ORIGINS is unset - the probe would run nothing and pass."
    bad "set it to a space-separated list, e.g."
    bad "  HBH_CI_ORIGINS='https://hbhskills.com https://apply.hbhskills.com'"
    record surface "FAIL-EMPTY" "no origins configured"
    return 1
  fi

  local log="$LOGDIR/surface.log" origin path code bad_count=0
  : >"$log"

  # The allowlist is the schema's, not the page's. .mp4 is here because
  # hbh.site_team_media carries a VIDEO row awaiting publication - the first
  # publish from that screen would 404 on the only thing it showed.
  local -a MUST_404=(
    /api/v1/auth/otp/request
    /api/v1/auth/staff/login
    /api/v1/children
    /healthz
    /README.md
    /CONTENT-AUDIT.md
    /.env
    /config.json
  )

  for origin in $origins; do
    for path in "${MUST_404[@]}"; do
      code="$(curl -s -o /dev/null -m 15 -w '%{http_code}' "$origin$path" 2>/dev/null)"
      if [ "$code" = "404" ] || [ "$code" = "000" ]; then
        printf '  OK      %-46s %s -> %s\n' "$origin" "$path" "$code" >>"$log"
      else
        printf '  REFUSED %-46s %s -> %s\n' "$origin" "$path" "$code" >>"$log"
        bad_count=$((bad_count + 1))
      fi
    done
  done

  cat "$log"
  local probes; probes="$(count_probes <"$log")"
  info "executed: $probes probe(s)"

  if [ "$probes" -eq 0 ]; then
    bad "zero probes ran"
    record surface "FAIL-EMPTY" "0 probes"
    return 1
  fi
  if [ "$bad_count" -gt 0 ]; then
    bad "$bad_count path(s) answered that must not be served"
    record surface "FAIL" "$bad_count of $probes answered"
    return 1
  fi
  record surface "PASS" "$probes probes, none answered"
  return 0
}

# ---------------------------------------------------------------------------
# --self-test
#
# Feeds every counter an empty transcript and a populated one. A counter
# that has only ever been seen returning a large number has not been shown
# to be reading anything.
# ---------------------------------------------------------------------------

self_test() {
  local fails=0

  check() {                       # name  expected  actual
    if [ "$2" = "$3" ]; then
      printf '  ok    %-24s -> %s\n' "$1" "$3"
    else
      printf '  FAIL  %-24s -> %s (wanted %s)\n' "$1" "$3" "$2"
      fails=$((fails + 1))
    fi
  }

  echo "=== empty transcript: every counter must say 0 ==="
  check count_db_checks    0 "$(printf ''  | count_db_checks)"
  check count_db_verdicts  0 "$(printf ''  | count_db_verdicts)"
  check count_go_packages  0 "$(printf ''  | count_go_packages)"
  check count_web_executed 0 "$(printf ''  | count_web_executed)"
  check count_probes       0 "$(printf ''  | count_probes)"

  echo
  echo "=== the transcript that lies: exit 0, nothing executed ==="
  check count_web_executed 0 "$(printf 'TOTAL: 0 SUCCESS\nExecuted 0 of 0\n' | count_web_executed)"
  check count_go_packages  0 "$(printf 'no test files\nno test files\n'      | count_go_packages)"
  check count_db_checks    0 "$(printf 'PHASE 00 ACCEPTED\n'                 | count_db_checks)"

  echo
  echo "=== real work: every counter must see it ==="
  check count_db_checks   119 "$(printf '  70 checks, 0 failed\n  49 checks, 0 failed\n' | count_db_checks)"
  check count_db_verdicts   2 "$(printf '  PHASE 00 ACCEPTED\n  PHASE a7 ACCEPTED\n'     | count_db_verdicts)"
  check count_go_packages   2 "$(printf 'ok  \thbh/api/store\tok\nok  \thbh/api/http\n'  | count_go_packages)"
  check count_web_executed 53 "$(printf 'Executed 41 of 41\nExecuted 12 of 12\n'         | count_web_executed)"
  check count_probes        2 "$(printf '  OK      a /x -> 404\n  REFUSED b /y -> 200\n' | count_probes)"

  echo
  if [ "$fails" != 0 ]; then
    echo "SELF-TEST NOT ACCEPTED - $fails counter(s) wrong"
    return 1
  fi
  echo "SELF-TEST ACCEPTED"
  return 0
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

case "${1:-}" in
  --list)      printf '%s\n' "${STAGES[@]}"; exit 0 ;;
  --self-test) self_test; exit $? ;;
esac

declare -a want=()
if [ "$#" -eq 0 ]; then
  want=("${STAGES[@]}")
else
  want=("$@")
fi

# A run that was asked for nothing valid is a failed run, not an empty one.
for s in "${want[@]}"; do
  case " ${STAGES[*]} " in
    *" $s "*) ;;
    *) echo "unknown stage: $s (see --list)" >&2; exit 2 ;;
  esac
done

echo "==========================================================="
echo " HBH CI - $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo " stages: ${want[*]}"
echo " logs:   $LOGDIR"
echo "==========================================================="

for s in "${want[@]}"; do
  echo
  hr
  echo "STAGE: $s"
  hr
  "stage_$s" || true
done

echo
echo "==========================================================="
printf '%s\n' "${RESULTS[@]}"
echo "-----------------------------------------------------------"
echo " passed: $PASSED    failed: $FAILED"
echo "==========================================================="

[ "$FAILED" -eq 0 ] || exit 1
# And a run in which nothing was judged is not a pass either.
[ "$PASSED" -gt 0 ] || { echo "*** nothing ran" >&2; exit 1; }
exit 0
