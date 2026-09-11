#!/usr/bin/env bash
# =====================================================================
# Hand By Hand (new) - INDEPENDENT API probe  (test-case set X2)
#
# Must print:  X2 ACCEPTED
#
#   API_BASE=http://127.0.0.1:8095 X2_CONTAINER=hbh-db-x1 \
#     bash tests/test-cases/run/x2_api_probe.sh
#
# tests/api/a1_verify.sh already proves the phase: the gate, the uniform
# login answer, the audit trail, the transport basics. This set does NOT
# repeat any of that. It asks the questions a suite written by the author
# of the endpoint tends not to ask - what happens on the inputs nobody
# meant to send:
#
#   hardening  a token offered anywhere other than the header
#   idor       an identifier that is not an identifier
#   input      a body that is not the body
#   privacy    what leaks in a header, an error, or a URL
#   session    one code, two callers, at the same instant
#   rate       whether a header the service says it does not trust can
#              still be used to walk around the limiter
#
# It inherits the five rules from tests/api/lib.sh, and the last group
# is deliberately last: it spends the limiter on purpose.
# =====================================================================

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../api" && pwd)/lib.sh"

# lib.sh reaches the database through docker compose. This set is meant
# to run against a private instance as well, because it exhausts a rate
# limiter and forges half-broken requests - not something to do to a
# colleague's run on the shared stack.
if [ -n "${X2_CONTAINER:-}" ]; then
  psqlq() { docker exec -i "$X2_CONTAINER" psql -tAqX -U hbh_owner -d hbh -c "$1" 2>/dev/null | tr -d '\r'; }
  psqlf() { docker exec -i "$X2_CONTAINER" psql -v ON_ERROR_STOP=1 -U hbh_owner -d hbh -f - < "$1" 2>&1; }
fi

echo "=================== X2 - independent API probe ==================="
echo "base: $API_BASE"
echo

# req_h <method> <path> <body> <token> <extra curl args...> -> status code
# The lib helper covers the ordinary shapes; this one is for the
# deliberately malformed ones - a wrong scheme, no content type, a
# header the service claims not to trust.
req_h() {
  local method="$1" path="$2" body="$3"; shift 3
  local -a args=(-sS -o "$BODY" -w '%{http_code}' -X "$method" "$API_BASE$path" "$@")
  if [ -n "$body" ]; then args+=(--data-binary "$body"); fi
  local code
  code="$(curl "${args[@]}" 2>"$TMP/curl.err")"
  [ -z "$code" ] && code="000"
  printf '%s' "$code"
}

# not5xx <group> <name> <status> - the weakest useful assertion, and the
# right one where the correct 4xx is a matter of taste but a 500 never is.
not5xx() {
  case "$3" in
    5*|000) chk "$1" "$2" 1 "got [$3]" ;;
    *)      chk "$1" "$2" 0 ;;
  esac
}

# =====================================================================
# FIXTURE - by name, before anything else
# =====================================================================
eq fixture 'service answers /healthz' '200' "$(req GET /healthz)"
eq fixture 'service answers /readyz'  '200' "$(req GET /readyz)"

MOBILE_A='01500000001'
MOBILE_B='01500000002'

CHILD_A="$(psqlq "SELECT child_id FROM hbh.children WHERE child_no = 'A1-A'")"
CHILD_B="$(psqlq "SELECT child_id FROM hbh.children WHERE child_no = 'A1-B'")"
chk fixture 'child A identifier known' "$([ -n "$CHILD_A" ] && echo 0 || echo 1)" 'A1-A missing - load tests/fixtures/a1_fixture.sql first'
chk fixture 'child B identifier known' "$([ -n "$CHILD_B" ] && echo 0 || echo 1)" 'A1-B missing - load tests/fixtures/a1_fixture.sql first'

# Parent A logs in through a mobile number wrapped in whitespace, which
# is what a phone keyboard hands over often enough to matter. Doing it
# here rather than in a probe of its own is deliberate: request_otp holds
# a resend cooldown, so a second request for the same number inside the
# window comes back 202 with no code at all - and a probe that reads that
# as "the number was not recognised" is measuring the cooldown, not the
# trimming. One request, and the code it returns proves both.
req POST /api/v1/auth/otp/request "{\"mobile\":\"  $MOBILE_A  \"}" >/dev/null
PAD_CODE="$(jstr "$BODY" dev_code)"
# Two runs of this file inside a minute land inside the resend cooldown,
# and the second one gets 202 with no code - which reads as "the padded
# number was not recognised" and is nothing of the sort. Wait it out once
# rather than leave the suite un-repeatable.
if [ -z "$PAD_CODE" ]; then
  echo '  ..    waiting out the resend cooldown (up to 65s)'
  sleep 65
  req POST /api/v1/auth/otp/request "{\"mobile\":\"  $MOBILE_A  \"}" >/dev/null
  PAD_CODE="$(jstr "$BODY" dev_code)"
fi
chk input 'a mobile wrapped in whitespace still reaches its own account' \
  "$([ -n "$PAD_CODE" ] && echo 0 || echo 1)" 'no code came back for the padded number'

req POST /api/v1/auth/otp/verify "{\"mobile\":\"$MOBILE_A\",\"code\":\"$PAD_CODE\"}" >/dev/null
TOKEN_A="$(jstr "$BODY" token)"
chk fixture 'parent A holds a session token' "$([ -n "$TOKEN_A" ] && echo 0 || echo 1)" 'login returned no token'
eq fixture 'and the token works' '200' "$(req GET /api/v1/me '' "$TOKEN_A")"

# =====================================================================
# GROUP: hardening - the token belongs in the header and nowhere else
#
# The contract says "in the header only, NEVER in a URL". A token in a
# query string is written to every access log and proxy cache between
# the phone and the service, so a service that also accepts it there has
# no way to keep that promise on the client's behalf.
# =====================================================================
eq hardening 'a valid token in ?token= does not authenticate' '401' \
  "$(req GET "/api/v1/me?token=$TOKEN_A")"
eq hardening 'a valid token in ?access_token= does not authenticate' '401' \
  "$(req GET "/api/v1/me?access_token=$TOKEN_A")"
eq hardening 'a valid token in a cookie does not authenticate' '401' \
  "$(req_h GET /api/v1/me '' -H "Cookie: token=$TOKEN_A")"
eq hardening 'a valid token in X-Auth-Token does not authenticate' '401' \
  "$(req_h GET /api/v1/me '' -H "X-Auth-Token: $TOKEN_A")"
eq hardening 'the Basic scheme is refused' '401' \
  "$(req_h GET /api/v1/me '' -H "Authorization: Basic $TOKEN_A")"
eq hardening 'an empty Bearer value is refused' '401' \
  "$(req_h GET /api/v1/me '' -H 'Authorization: Bearer ')"
eq hardening 'the word Bearer alone is refused' '401' \
  "$(req_h GET /api/v1/me '' -H 'Authorization: Bearer')"
eq hardening 'a fabricated token of the right shape is refused' '401' \
  "$(req GET /api/v1/me '' "$(printf 'a%.0s' $(seq 1 43))")"
not5xx hardening 'a ten kilobyte token does not crash the service' \
  "$(req GET /api/v1/me '' "$(printf 'a%.0s' $(seq 1 10240))")"
eq hardening 'a token with a trailing newline is refused' '401' \
  "$(req_h GET /api/v1/me '' -H "Authorization: Bearer ${TOKEN_A}%0a")"
eq hardening 'a refused request names UNAUTHENTICATED' 'UNAUTHENTICATED' \
  "$(req GET /api/v1/me >/dev/null; jstr "$BODY" code)"

# =====================================================================
# GROUP: idor - an identifier that is not an identifier
#
# The gate itself is a1's job. This group is about the handler's edges:
# every one of these must come back as a clean refusal, never as a 500,
# and never with a database error inside it. A schema name in an error
# body is a map handed to whoever asked for it.
# =====================================================================
for bad in 'abc' '-1' '0' '99999999999999999999' '1.5' '%201' 'null' 'NaN' '1%20OR%201%3D1' "1%27%3B--"; do
  not5xx idor "an identifier of [$bad] is refused cleanly" "$(req GET "/api/v1/children/$bad" '' "$TOKEN_A")"
done

req GET "/api/v1/children/abc" '' "$TOKEN_A" >/dev/null
eq idor 'the refusal is JSON with a code' 'yes' "$(jhas "$BODY" code)"
LEAK="$(grep -ciE 'pgx|sqlstate|pq:|panic|goroutine|hbh\.|postgres|relation' "$BODY" || true)"
eq idor 'no database internals in the error body' '0' "$LEAK"

req GET "/api/v1/children/$CHILD_B" '' "$TOKEN_A" >/dev/null
eq idor "another family's child is NOT_FOUND, not FORBIDDEN" 'NOT_FOUND' "$(jstr "$BODY" code)"
eq idor 'and it carries no hint that the row exists' '0' \
  "$(grep -ciE 'forbidden|denied|permission|exists' "$BODY" || true)"

not5xx idor 'a traversal in the path is refused cleanly' \
  "$(req GET '/api/v1/children/..%2f..%2fme' '' "$TOKEN_A")"

# =====================================================================
# GROUP: input - a body that is not the body
# =====================================================================
eq input 'a body that is not JSON is a 400' '400' \
  "$(req_h POST /api/v1/auth/otp/request 'not json at all' -H 'Content-Type: application/json')"
eq input 'and it names VALIDATION' 'VALIDATION' "$(jstr "$BODY" code)"
eq input 'an empty body is a 400' '400' \
  "$(req_h POST /api/v1/auth/otp/request '' -H 'Content-Type: application/json')"
eq input 'a JSON array instead of an object is a 400' '400' \
  "$(req POST /api/v1/auth/otp/request '[]')"
eq input 'a mobile sent as a number is a 400' '400' \
  "$(req POST /api/v1/auth/otp/request '{"mobile":1500000001}')"
eq input 'a null mobile is a 400' '400' \
  "$(req POST /api/v1/auth/otp/request '{"mobile":null}')"
eq input 'an unknown field is a 400' '400' \
  "$(req POST /api/v1/auth/otp/request "{\"mobile\":\"$MOBILE_A\",\"role\":\"ADMIN\"}")"
eq input 'a mobile that does not match the pattern is a 400' '400' \
  "$(req POST /api/v1/auth/otp/request '{"mobile":"12345"}')"
# Surrounding whitespace is TRIMMED rather than refused - see the login
# in the fixture, which goes through a padded number on purpose. The
# contract does not mention the normalisation; that is a gap in the
# document, not a hole in the service.
# An unregistered number, so this probe spends nobody's resend cooldown
# and the race group below still gets a fresh code for parent B.
eq input 'a mobile with surrounding spaces is accepted, not refused' '202' \
  "$(req POST /api/v1/auth/otp/request '{"mobile":"  01599999999  "}')"
# Arabic-Indic digits are what an Egyptian keyboard produces by default.
# They are not the pattern, so this must be a judgement on shape - and
# it must be a judgement, not a crash.
eq input 'a mobile in Arabic-Indic digits is a 400' '400' \
  "$(req POST /api/v1/auth/otp/request '{"mobile":"٠١٥٠٠٠٠٠٠٠١"}')"
# From a FILE, not from the command line. A megabyte of argv dies in the
# shell on this host with "Argument list too long" and curl never runs -
# which reads as a dead service and is nothing of the kind. That false
# alarm cost a round of investigation once already.
printf '{"mobile":"' > "$TMP/big.json"
head -c 10485760 /dev/zero | tr '\0' 'a' >> "$TMP/big.json"
printf '"}' >> "$TMP/big.json"
eq input 'a ten megabyte body is refused, not swallowed' '400' \
  "$(req_h POST /api/v1/auth/otp/request '' -H 'Content-Type: application/json' --data-binary "@$TMP/big.json")"
eq input 'and the refusal is the ordinary validation code' 'VALIDATION' "$(jstr "$BODY" code)"
not5xx input 'a verify with no code does not crash the service' \
  "$(req POST /api/v1/auth/otp/verify "{\"mobile\":\"$MOBILE_A\"}")"
not5xx input 'a verify with a non-numeric code does not crash the service' \
  "$(req POST /api/v1/auth/otp/verify "{\"mobile\":\"$MOBILE_A\",\"code\":\"abcdef\"}")"
eq input 'the mobile cannot be smuggled in as a query parameter' '400' \
  "$(req_h POST "/api/v1/auth/otp/request?mobile=$MOBILE_A" '' -H 'Content-Type: application/json')"

# =====================================================================
# GROUP: privacy - what leaks in a header or an error
# =====================================================================
req POST /api/v1/auth/otp/request "{\"mobile\":\"$MOBILE_A\"}" >/dev/null
eq privacy 'the request response does not echo the mobile number' '0' \
  "$(grep -c "$MOBILE_A" "$BODY" || true)"

curl -sS -D "$TMP/hdr" -o /dev/null "$API_BASE/healthz"
eq privacy 'no Server header naming the runtime' '0' \
  "$(grep -ci '^server:' "$TMP/hdr" || true)"
eq privacy 'no X-Powered-By header' '0' \
  "$(grep -ci '^x-powered-by:' "$TMP/hdr" || true)"
eq privacy 'content type sniffing is refused' '1' \
  "$(grep -ci '^x-content-type-options: *nosniff' "$TMP/hdr" || true)"

curl -sS -D "$TMP/hdr" -o /dev/null "$API_BASE/api/v1/me"
eq privacy 'an unauthenticated refusal still carries a request id' '1' \
  "$(grep -ci '^x-request-id:' "$TMP/hdr" || true)"
eq privacy 'and the refusal is JSON, not HTML' '1' \
  "$(grep -ci '^content-type: *application/json' "$TMP/hdr" || true)"

# A wrong code is the one refusal that carries a number back to the
# caller. It must carry the count and nothing else about the account.
req POST /api/v1/auth/otp/verify "{\"mobile\":\"$MOBILE_B\",\"code\":\"000000\"}" >/dev/null
eq privacy 'a wrong code does not name the account holder' '0' \
  "$(grep -ciE 'full_name|username|user_id|الطفل' "$BODY" || true)"

# =====================================================================
# GROUP: session - one code, two callers, the same instant
#
# a1 proves a code is single use when the two attempts are sequential.
# Sequential is the easy half. Two verifies racing on the same code is
# where a check-then-write would hand out two sessions.
# =====================================================================
req POST /api/v1/auth/otp/request "{\"mobile\":\"$MOBILE_B\"}" >/dev/null
RACE_CODE="$(jstr "$BODY" dev_code)"
chk session 'a fresh code was issued for the race' "$([ -n "$RACE_CODE" ] && echo 0 || echo 1)" 'no dev_code in the response'

curl -sS -o "$TMP/r1" -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
  --data-binary "{\"mobile\":\"$MOBILE_B\",\"code\":\"$RACE_CODE\"}" \
  "$API_BASE/api/v1/auth/otp/verify" > "$TMP/c1" 2>/dev/null &
curl -sS -o "$TMP/r2" -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
  --data-binary "{\"mobile\":\"$MOBILE_B\",\"code\":\"$RACE_CODE\"}" \
  "$API_BASE/api/v1/auth/otp/verify" > "$TMP/c2" 2>/dev/null &
wait
RACE_OK=$(( $(cat "$TMP/c1") == 200 ? 1 : 0 ))
RACE_OK=$(( RACE_OK + ( $(cat "$TMP/c2") == 200 ? 1 : 0 ) ))
eq session 'two callers racing on one code get exactly one session' '1' "$RACE_OK"
neq session 'and neither of them got a 500' '5' "$(cut -c1 "$TMP/c1")"
neq session 'nor did the other' '5' "$(cut -c1 "$TMP/c2")"

# The winner of the race is a live session, so it is the one to log out
# - and no further one-time code is asked for. request_otp holds a
# resend cooldown of its own, so a suite that logs the same account in
# twice in a row gets no second code and reads it as a broken login. It
# already did, once, in this file.
RACE_TOKEN="$(jstr "$TMP/r1" token)"
[ -z "$RACE_TOKEN" ] && RACE_TOKEN="$(jstr "$TMP/r2" token)"
chk session 'the winner of the race holds a usable session' \
  "$([ -n "$RACE_TOKEN" ] && echo 0 || echo 1)" 'neither response carried a token'

req POST /api/v1/auth/logout '' "$RACE_TOKEN" >/dev/null
eq session 'logging out twice with the same token is a 401' '401' \
  "$(req POST /api/v1/auth/logout '' "$RACE_TOKEN")"
eq session 'another account is untouched by that logout' '200' \
  "$(req GET /api/v1/me '' "$TOKEN_A")"

eq session 'every stored session expiry is in the future and in UTC' 'yes' \
  "$(psqlq "SELECT CASE WHEN count(*) = 0 THEN 'yes' ELSE 'no' END FROM hbh.auth_sessions WHERE expires_at <= now()")"

# =====================================================================
# GROUP: rate - LAST, because it spends the limiter on purpose
#
# The service is configured with TRUST_PROXY=false, so X-Forwarded-For
# is a client-written header and must not be believed. If it were, a
# caller walking a list of numbers would rotate the header and never be
# limited at all - which is the exact attack the limiter exists for,
# since request_otp throttles one ACCOUNT and every number on the list
# is a first attempt for its own account.
# =====================================================================
LIMITED=0
i=0
while [ "$i" -lt 90 ]; do
  code="$(req_h POST /api/v1/auth/otp/request "{\"mobile\":\"015000000$(printf '%02d' $((i % 90)))\"}" \
           -H 'Content-Type: application/json' \
           -H "X-Forwarded-For: 10.0.$((i / 250)).$((i % 250))")"
  if [ "$code" = "429" ]; then LIMITED=1; break; fi
  i=$((i + 1))
done
eq rate 'a rotating X-Forwarded-For does not walk around the limiter' '1' "$LIMITED"
eq rate 'the refusal names RATE_LIMITED' 'RATE_LIMITED' "$(jstr "$BODY" code)"
# One bucket per caller address, shared by both login paths - so the
# spent limiter must refuse verify too. Tried a few times in a tight
# loop, because the bucket refills at one token a second and a single
# probe taken a second later reads as "not limited" when the truth is
# only that it waited. That false alarm cost a round here already.
VERIFY_LIMITED=0
i=0
while [ "$i" -lt 6 ]; do
  if [ "$(req POST /api/v1/auth/otp/verify "{\"mobile\":\"$MOBILE_A\",\"code\":\"000000\"}")" = "429" ]; then
    VERIFY_LIMITED=1; break
  fi
  i=$((i + 1))
done
eq rate 'the verify endpoint shares the same bucket' '1' "$VERIFY_LIMITED"
eq rate 'the portal is not taken down with the login endpoints' '200' \
  "$(req GET /api/v1/me '' "$TOKEN_A")"
eq rate 'and health stays answerable while the limiter is spent' '200' "$(req GET /healthz)"

# =====================================================================
# CLEANUP - a recorded check
# =====================================================================
psqlq "DELETE FROM hbh.auth_sessions WHERE user_id IN (SELECT user_id FROM hbh.users WHERE username LIKE 'a1\\_%')" >/dev/null
eq cleanup 'no probe sessions are left behind' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.auth_sessions s JOIN hbh.users u ON u.user_id = s.user_id WHERE u.username LIKE 'a1\\_%'")"

verdict 'X2'
