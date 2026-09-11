#!/usr/bin/env bash
# =====================================================================
# Hand By Hand (new) - shared harness for the API acceptance suites
#
# Sourced by tests/api/aN_verify.sh. It carries the five rules the SQL
# suites are built on, so that a new batch inherits them instead of
# re-deciding them:
#
#   1. The verdict ALWAYS prints. Nothing here uses `set -e`: a probe
#      that dies records a failure rather than taking the run with it.
#      A suite that exits before its verdict reads as a pass.
#   2. A negative test names the error CODE it expects. A refusal for
#      the wrong reason proves nothing and looks green.
#   3. The fixture is asserted by name, before the tests.
#   4. Cleanup is a recorded check.
#   5. Counts against the append-only audit log are scoped to the run.
#
# Every helper writes the last response body to $BODY.
# =====================================================================

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="$ROOT/deploy/compose/docker-compose.yml"
API_BASE="${API_BASE:-http://127.0.0.1:8090}"
TMP="$(mktemp -d)"
BODY="$TMP/body"
HDR="$TMP/hdr"
JAR="$TMP/jar"

PASS=0
FAIL=0
declare -a FAILURES=()

trap 'rm -rf "$TMP"' EXIT

chk() { # chk <group> <name> <0|1> [detail]
  local grp="$1" name="$2" ok="$3" detail="${4:-}"
  if [ "$ok" = "0" ]; then
    PASS=$((PASS + 1))
    printf '  ok    %-9s %s\n' "$grp" "$name"
  else
    FAIL=$((FAIL + 1))
    FAILURES+=("$grp/$name: $detail")
    printf '  FAIL  %-9s %s  --  %s\n' "$grp" "$name" "$detail"
  fi
}

eq() { # eq <group> <name> <expected> <actual>
  if [ "$3" = "$4" ]; then chk "$1" "$2" 0; else chk "$1" "$2" 1 "expected [$3], got [$4]"; fi
}

neq() { # neq <group> <name> <not-expected> <actual>
  if [ "$3" != "$4" ]; then chk "$1" "$2" 0; else chk "$1" "$2" 1 "value must not be [$3]"; fi
}

ok_if() { # ok_if <group> <name> <shell-condition-result> <detail>
  chk "$1" "$2" "$3" "${4:-}"
}

# req <method> <path> [json body] [bearer token] -> prints the status code.
#
# Response headers land in $HDR and cookies in $JAR, because the live stream
# is delivered through an HttpOnly cookie the browser never shows to script -
# so a suite that could not read Set-Cookie could not test it at all.
req() {
  local method="$1" path="$2" body="${3:-}" token="${4:-}"
  local -a args=(-sS -o "$BODY" -D "$HDR" -c "$JAR" -b "$JAR"
                 -w '%{http_code}' -X "$method" "$API_BASE$path")
  if [ -n "$body" ]; then
    # The body goes through a FILE, never on the command line.
    #
    # curl here is a native Windows binary, and MSYS converts its argv to
    # the ANSI codepage on the way in - so Arabic passed as an argument
    # arrives as a row of question marks and is stored that way. The
    # damage is silent: the request succeeds, the row is written, and only
    # a byte-level look at the column shows 0x3f where the name should be.
    #
    # printf is a bash builtin, so writing the file does no conversion.
    printf '%s' "$body" > "$TMP/req.json"
    args+=(-H 'Content-Type: application/json' --data-binary "@$TMP/req.json")
  fi
  if [ -n "$token" ]; then args+=(-H "Authorization: Bearer $token"); fi
  local code
  code="$(curl "${args[@]}" 2>"$TMP/curl.err")"
  if [ -z "$code" ]; then code="000"; fi
  printf '%s' "$code"
}

# reqfile <method> <path> <file> <mime> [token] [extra-field] [extra-value]
#   -> prints the status code, same as req.
#
# The upload twin of req(). Every file route in this service takes
# multipart with the part named `file`, and sending a raw body instead
# reaches the handler as a zero-field form - which answers 400 and reads
# like a rejected file rather than a malformed request.
#
# THE PATH IS CONVERTED WITH `pwd -W`. curl here is a native Windows
# binary and does not understand /tmp/x or /c/Users/...; it opens
# nothing, curl exits 26, and the probe records 000 with no hint that
# the FILE was the problem and not the route.
reqfile() {
  local method="$1" path="$2" file="$3" mime="$4" token="${5:-}"
  local field="${6:-}" value="${7:-}"

  local win
  win="$(cd "$(dirname "$file")" && pwd -W 2>/dev/null || dirname "$file")/$(basename "$file")"

  local -a args=(-sS -o "$BODY" -D "$HDR" -c "$JAR" -b "$JAR"
                 -w '%{http_code}' -X "$method" "$API_BASE$path"
                 -F "file=@$win;type=$mime")
  if [ -n "$field" ]; then args+=(-F "$field=$value"); fi
  if [ -n "$token" ]; then args+=(-H "Authorization: Bearer $token"); fi

  local code
  code="$(curl "${args[@]}" 2>"$TMP/curl.err")"
  if [ -z "$code" ]; then code="000"; fi
  printf '%s' "$code"
}

# hdr <name> -> the value of one response header from the last req.
hdr() { tr -d '\r' < "$HDR" | sed -n "s/^$1: //Ip" | head -1; }

# setcookie -> the raw Set-Cookie line from the last req.
setcookie() { tr -d '\r' < "$HDR" | sed -n 's/^[Ss]et-[Cc]ookie: //p' | head -1; }

# jar_clear forgets every cookie. Called between callers so one family's
# stream cookie cannot be carried into another family's request.
jar_clear() { : > "$JAR"; }

# Field readers. There is no jq on this machine and the responses are
# flat enough, so sed is enough - and one fewer thing to install (D-9).
#
# Note the greedy .* : these return the LAST occurrence of a key on the
# line. That is fine for a single object and wrong for a list, so a
# check over a list counts occurrences instead of reading one.
jstr()  { sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -1; }
jnum()  { sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*\(-\{0,1\}[0-9][0-9.]*\).*/\1/p' "$1" | head -1; }
jbool() { sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' "$1" | head -1; }
jhas()  { if grep -q "\"$2\"" "$1"; then echo yes; else echo no; fi; }
jcount() { grep -o "\"$2\"" "$1" | wc -l | tr -d ' '; }

dc()    { docker compose -f "$COMPOSE_FILE" "$@"; }
psqlq() { dc exec -T db psql -tAqX -U hbh_owner -d hbh -c "$1" 2>/dev/null | tr -d '\r'; }
psqlf() { dc exec -T db psql -v ON_ERROR_STOP=1 -U hbh_owner -d hbh -f - < "$1" 2>&1; }

# login <mobile> -> prints a session token, or nothing.
#
# Uses the development echo, because there is no SMS gateway yet and the
# suite has no other way to learn the code. config.Load refuses to start
# a non-development process with OTP_ECHO on.
login() {
  local mobile="$1" code
  req POST /api/v1/auth/otp/request "{\"mobile\":\"$mobile\"}" >/dev/null
  code="$(jstr "$BODY" dev_code)"
  if [ -z "$code" ]; then return 1; fi
  req POST /api/v1/auth/otp/verify "{\"mobile\":\"$mobile\",\"code\":\"$code\"}" >/dev/null
  jstr "$BODY" token
}

# verdict <label> - prints the tally and exits non-zero on any failure.
# The exit happens AFTER the verdict, so the verdict is never skipped.
verdict() {
  local label="$1"
  echo
  if [ "${#FAILURES[@]}" -gt 0 ]; then
    echo 'failures:'
    local i=0
    while [ "$i" -lt "${#FAILURES[@]}" ]; do
      echo "  - ${FAILURES[$i]}"
      i=$((i + 1))
    done
    echo
  fi

  local total=$((PASS + FAIL))
  echo '--------------------------------------------------'
  printf '  %s checks, %s failed\n' "$total" "$FAIL"
  if [ "$FAIL" = "0" ] && [ "$total" -gt 0 ]; then
    echo "  $label ACCEPTED"
  else
    echo "  *** $label NOT ACCEPTED"
  fi
  echo '--------------------------------------------------'

  # An explicit 1, never "${rc:-1}": a `local out rc=0` sets rc and the
  # fallback never fires, which reads a failure as a pass.
  if [ "$FAIL" != "0" ] || [ "$total" = "0" ]; then
    exit 1
  fi
  exit 0
}

# staff_login <username> <password> -> prints a session token, or nothing.
#
# Staff sign in with a password and families with a one-time code, and
# hbh.verify_password refuses to let the two paths cross.
staff_login() {
  req POST /api/v1/auth/staff/login "{\"username\":\"$1\",\"password\":\"$2\"}" >/dev/null
  jstr "$BODY" token
}

# psqlapp <sql> - runs SQL as hbh_app, the role the API actually connects as.
#
# psqlq runs as the OWNER, which bypasses every policy - useful for building a
# fixture, useless for proving one. This is how a suite asserts what a policy
# does rather than what it says.
psqlapp() {
  dc exec -T -e PGPASSWORD="${DB_APP_PASSWORD:-hbh_app_dev_only_change_me}" db \
    psql -tAqX -U hbh_app -h 127.0.0.1 -d hbh -c "$1" 2>&1 | tr -d '\r'
}
