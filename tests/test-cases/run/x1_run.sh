#!/usr/bin/env bash
# =====================================================================
# Runner for the independent isolation sweep (test-case set X1).
#
#   bash tests/test-cases/run/x1_run.sh
#
# It decides on the verdict LINE, not on psql's exit code: the suite
# runs with ON_ERROR_STOP off so every probe records its own failure,
# which means psql can finish happily on a suite that failed.
# =====================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
COMPOSE_FILE="$ROOT/deploy/compose/docker-compose.yml"

if [ -f "$ROOT/.env" ]; then
  set -a; . "$ROOT/.env"; set +a
fi
: "${DB_OWNER_PASSWORD:=hbh_dev_only_change_me}"
: "${DB_PORT:=5434}"
export DB_OWNER_PASSWORD DB_PORT

# The suite drops and recreates its own harness schema, and it builds a
# whole second centre. Two runs against one database therefore tear each
# other's fixture down mid-flight - which has already happened here once,
# against a colleague's phase run. X1_CONTAINER points this at a private
# instance; unset, it uses the shared development database.
if [ -n "${X1_CONTAINER:-}" ]; then
  out="$(docker exec -i "$X1_CONTAINER" psql -U hbh_owner -d hbh -f - \
          < "$ROOT/tests/test-cases/run/x1_isolation_sweep.sql" 2>&1)" || true
else
  out="$(docker compose -f "$COMPOSE_FILE" exec -T db \
          psql -U hbh_owner -d hbh -f - \
          < "$ROOT/tests/test-cases/run/x1_isolation_sweep.sql" 2>&1)" || true
fi
echo "$out"

if echo "$out" | grep -q 'X1 ACCEPTED'; then
  exit 0
fi

echo
if echo "$out" | grep -q 'NOT ACCEPTED'; then
  echo '*** X1 ran and was refused - see the failures above' >&2
else
  echo '*** X1 did not reach its verdict at all - treat this as a failure' >&2
fi
exit 1
