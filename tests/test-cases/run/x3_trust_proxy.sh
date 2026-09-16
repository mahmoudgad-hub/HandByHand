#!/usr/bin/env bash
# =====================================================================
# X3 — the caller's address, end to end (HBH-005)
#
# Must print:  X3 ACCEPTED
#
#   bash tests/test-cases/run/x3_trust_proxy.sh
#
# ---------------------------------------------------------------------
# WHY THIS RUNS ITS OWN SERVICE INSTEAD OF JOINING THE OTHER SUITES
#
# Every other API suite talks to the compose service, and that service
# has TRUST_PROXY=false and no proxy in front of it - correctly, because
# nothing proxies it. A suite pointed at that process can only ever prove
# the header is ignored, which is half the card and the easy half.
#
# The behaviour being accepted here belongs to a DIFFERENT configuration:
# the one in deploy/server, where nginx sits in front and TRUST_PROXY is
# true. So this probe starts a throwaway service with that configuration,
# on a spare port, against the same database, and stops it again.
#
# ---------------------------------------------------------------------
# WHAT IS PROVED, AND WHY THE SECOND CASE IS THE IMPORTANT ONE
#
#   1. TRUSTED peer   the forwarded address reaches hbh.audit_log AS
#                     ITSELF - not as the gateway, which is what every
#                     row said before this card.
#   2. APPENDED list  nginx sets the header with
#                     $proxy_add_x_forwarded_for, which APPENDS the peer
#                     it saw to whatever the client sent. So a caller can
#                     put their own value in front of the real one. The
#                     address recorded must be the LAST entry.
#   3. UNTRUSTED peer a caller reaching the socket directly, with a
#                     header it wrote itself, is recorded by its real
#                     address. This is the one that fails if somebody
#                     "simplifies" the check to the flag alone.
#
# The rows are found by the USERNAME each attempt used, which is unique
# per run. Reading "the most recent deny" would pick up whatever another
# session on this shared database did a second earlier - the lesson a5
# paid for.
# =====================================================================
set -u
set -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
IMAGE="${IMAGE:-hbh-api}"
PORT="${PORT:-8097}"
NAME="hbh-x3-trustproxy"
NET="${NET:-hbh_default}"
FORGED="203.0.113.45"
REAL_CLAIM="198.51.100.9"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok    %-9s %s\n' "$1" "$2"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %-9s %s  --  %s\n' "$1" "$2" "$3"; }
eq()   { if [ "$3" = "$4" ]; then ok "$1" "$2"; else bad "$1" "$2" "expected [$3], got [$4]"; fi; }
ne()   { if [ "$3" != "$4" ]; then ok "$1" "$2"; else bad "$1" "$2" "should not have been [$3]"; fi; }

psqlq() {
  MSYS_NO_PATHCONV=1 docker exec -i hbh-db \
    psql -U hbh_owner -d hbh -tAq -c "$1" 2>/dev/null | tr -d '\r'
}

cleanup() {
  MSYS_NO_PATHCONV=1 docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ---------------------------------------------------------------------
# start_api <trusted-proxies-cidr>
#
# SMS_PROVIDER is pinned to dev rather than inherited. The compose .env
# may name a real provider whose credentials are not in this shell, and
# hbhd refuses to start without them - a refusal that has nothing to do
# with what is being tested and reads as though this probe broke.
# ---------------------------------------------------------------------
start_api() {
  cleanup
  MSYS_NO_PATHCONV=1 docker run -d --name "$NAME" --network "$NET" \
    -p "127.0.0.1:${PORT}:8090" \
    -e APP_ENV=development \
    -e API_LISTEN=":8090" \
    -e DATABASE_URL="postgres://hbh_app:${DB_APP_PASSWORD:-hbh_app_dev_only_change_me}@db:5432/hbh?sslmode=disable" \
    -e LOG_LEVEL=warn \
    -e OTP_ECHO=true \
    -e SMS_PROVIDER=dev \
    -e TRUST_PROXY=true \
    -e TRUSTED_PROXIES="$1" \
    -e AUTH_RATE_PER_MINUTE=600 \
    -e TZ=UTC \
    "$IMAGE" >/dev/null 2>&1 || return 1

  local i=0
  while [ "$i" -lt 40 ]; do
    if curl -s -o /dev/null "http://127.0.0.1:${PORT}/healthz" 2>/dev/null; then return 0; fi
    i=$((i+1)); sleep 0.5
  done
  echo "  the throwaway service never became reachable. Last lines:" >&2
  docker logs --tail 5 "$NAME" 2>&1 | sed 's/^/    /' >&2
  return 1
}

# attempt <username> <x-forwarded-for>  -> writes one DENY row
attempt() {
  curl -s -o /dev/null -X POST "http://127.0.0.1:${PORT}/api/v1/auth/staff/login" \
    -H 'Content-Type: application/json' \
    -H "X-Forwarded-For: $2" \
    -d "{\"username\":\"$1\",\"password\":\"certainly-not-the-password\"}"
}

recorded_ip() {
  psqlq "SELECT coalesce(host(client_ip), '(null)') FROM hbh.audit_log
         WHERE changed_by = '$1' AND detail LIKE 'STAFF_LOGIN%'
         ORDER BY changed_at DESC LIMIT 1"
}

STAMP="$(date +%s)"

echo "=================================================="
echo "  X3 — the caller's address reaches the audit log"
echo "=================================================="

# =====================================================================
# CASE 1 — the peer IS the proxy
# =====================================================================
U1="x3.trusted.$STAMP"
U2="x3.appended.$STAMP"
if start_api "0.0.0.0/0,::/0"; then
  ok start "a service with TRUST_PROXY=true is listening"

  attempt "$U1" "$FORGED"
  eq trusted 'the forwarded address reaches audit_log as itself' "$FORGED" "$(recorded_ip "$U1")"

  # The shape nginx actually produces: the client's own value, then the
  # address nginx saw, appended.
  attempt "$U2" "${REAL_CLAIM}, ${FORGED}"
  eq trusted 'an appended list records the entry the proxy wrote' "$FORGED" "$(recorded_ip "$U2")"
  ne trusted 'and not the entry the caller put in front of it' "$REAL_CLAIM" "$(recorded_ip "$U2")"
else
  bad start 'a service with TRUST_PROXY=true is listening' 'it did not start'
  bad trusted 'the forwarded address reaches audit_log as itself' 'no service'
  bad trusted 'an appended list records the entry the proxy wrote' 'no service'
  bad trusted 'and not the entry the caller put in front of it' 'no service'
fi

# =====================================================================
# CASE 2 — the peer is NOT the proxy
#
# Same flag, same header, same service. The only thing that changed is
# that this caller is not on the trust list - which is every caller that
# reaches the socket without going through nginx.
# =====================================================================
U3="x3.untrusted.$STAMP"
if start_api "10.99.99.99/32"; then
  ok start 'a service that trusts a different peer is listening'

  attempt "$U3" "$FORGED"
  GOT="$(recorded_ip "$U3")"
  ne untrusted 'a forged header from a direct caller is not believed' "$FORGED" "$GOT"
  # And it is not a hole either: something real was recorded.
  if [ -n "$GOT" ] && [ "$GOT" != "(null)" ]; then
    ok untrusted "the socket address was recorded instead ($GOT)"
  else
    bad untrusted 'the socket address was recorded instead' "got [$GOT]"
  fi
else
  bad start 'a service that trusts a different peer is listening' 'it did not start'
  bad untrusted 'a forged header from a direct caller is not believed' 'no service'
  bad untrusted 'the socket address was recorded instead' 'no service'
fi

cleanup

echo ""
echo "--------------------------------------------------"
printf '  %s checks, %s failed\n' "$((PASS+FAIL))" "$FAIL"
if [ "$FAIL" -eq 0 ]; then
  echo "  X3 ACCEPTED"
  echo "--------------------------------------------------"
  exit 0
fi
echo "  *** X3 NOT ACCEPTED"
echo "--------------------------------------------------"
exit 1
