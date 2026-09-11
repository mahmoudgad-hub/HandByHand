#!/usr/bin/env bash
# =====================================================================
# Hand By Hand (new) - W2: a build that warns is a build that failed
#
# Why this suite exists, in one sentence: a CSS rule was silently
# DELETED from the portal for days and the only trace was one line in a
# successful build.
#
# What happened. A comment in portal.css lost its opening, which left a
# stray comment-close sitting where a selector belongs. The parser threw
# away the rule after it - the breadcrumb - and said so:
#
#   1 rules skipped due to selector errors
#
# as a WARNING, inside a build that ended "Application bundle generation
# complete". Nothing failed. It scrolled past several times before
# anybody read it. And the first repair REINTRODUCED it, by quoting a
# comment-close inside a comment while explaining the problem - two
# broken comments instead of one, and again a successful build.
#
# The lesson is not about CSS comments. It is that a warning inside a
# green build is the most expensive kind of defect signal there is,
# because it is indistinguishable from success at a glance. So this
# turns the whole class into a gate: both applications must build with
# NO warnings at all, and a new warning of any kind stops the run.
#
# It follows the same rules as W1 and tests/api/lib.sh:
#   1. The verdict ALWAYS prints. No `set -e`.
#   2. A check names what it expected, not just that something is wrong.
#   3. Exceptions would live in a file with a written reason. There are
#      none, and an empty exemption list is the point: the day one is
#      needed it is a decision somebody writes down.
#   4. The check is structural - it catches a NEW warning, not only the
#      two that are known today.
# =====================================================================

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEB="$ROOT/web"

passed=0
failed=0
failures=()

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    failures+=("$name: expected $expected, got $actual")
  fi
}

# ---------------------------------------------------------------------
# The fixture, asserted by name before anything is tested. A suite that
# silently tested nothing because a path moved is worse than no suite.
# ---------------------------------------------------------------------
for f in "$WEB/angular.json" "$WEB/package.json"; do
  if [ ! -f "$f" ]; then
    echo "  W2 FIXTURE MISSING: $f" >&2
    echo "  W2 FAILED" >&2
    exit 1
  fi
done

if ! command -v node >/dev/null 2>&1; then
  echo "  W2 SKIPPED: node is not on PATH" >&2
  exit 0
fi

# ---------------------------------------------------------------------
# Build each application and count what the compiler complained about.
#
# The output is stripped of ANSI colour first: the build writes escape
# codes, and grepping for a word that has a colour code in the middle of
# it finds nothing and reports a clean build.
# ---------------------------------------------------------------------
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

for project in ops portal; do
  # The build writes to a FILE and its own exit status is read directly.
  #
  # Not `out="$(ng build | sed ...)"; rc=$?`. That reads the status of a
  # PIPELINE, and the first run of this suite reported 1 for both
  # projects while every other check on the same output passed - a build
  # that had plainly succeeded, called a failure. Two later runs,
  # including one on a cold cache, could not reproduce it. An
  # intermittent gate is worse than no gate, because the first false
  # alarm teaches everyone to re-run it, and the second real one is
  # re-run too. So the ambiguity is removed rather than explained.
  (cd "$WEB" && npx ng build "$project") > "$log" 2>&1
  rc=$?

  # Colour codes are stripped when the log is READ, not while it is
  # captured: grepping for a word with an escape sequence inside it finds
  # nothing and reports a clean build.
  clean="$(sed 's/\x1b\[[0-9;]*m//g' "$log")"

  # The exit status first. A build that fell over has not "passed with
  # warnings" - there is no output worth inspecting at all.
  check "$project builds" "0" "$rc"

  warnings="$(printf '%s\n' "$clean" | grep -c '\[WARNING\]')"
  check "$project builds with no warnings" "0" "$warnings"

  # Named separately, because this is the one that started it: a count
  # alone would not say WHICH warning had come back.
  skipped="$(printf '%s\n' "$clean" | grep -c 'rules skipped due to selector errors')"
  check "$project drops no CSS rules" "0" "$skipped"

  if [ "$rc" != "0" ] || [ "$warnings" != "0" ]; then
    printf '%s\n' "$clean" | grep -A 4 -E '\[WARNING\]|\[ERROR\]' | sed 's/^/      /'
  fi
done

# ---------------------------------------------------------------------
# The verdict prints whatever happened above, and only then does the
# exit code become non-zero.
# ---------------------------------------------------------------------
echo "  ----------------------------------------"
if [ "$failed" -ne 0 ]; then
  echo "  failures:"
  for line in "${failures[@]}"; do
    echo "    - $line"
  done
fi
echo "  passed $passed, failed $failed"

if [ "$failed" -ne 0 ]; then
  echo "  W2 FAILED"
  exit 1
fi
echo "  W2 PASSED"
