#!/usr/bin/env bash
# One maintenance run. The compose file gives this to a container that
# loops with sleep; here cron does the looping, so this does exactly one
# pass and exits.
#
# A failure is not fatal to anything: the run records itself in
# hbh.maintenance_runs either way, and hbh.v_maintenance_health is what
# says whether the work is actually happening. That view going stale is
# the signal to watch, not this script's exit code, because a cron job
# that never fires produces no failure at all.
set -uo pipefail

ROOT="$HOME/hand-by-hand"
PGBIN="$HOME/pgsql/usr/lib/postgresql/17/bin"
export LD_LIBRARY_PATH="$HOME/pgsql/deps"

set -a; . "$ROOT/.env"; set +a
DB_PORT="${DB_PORT:-5434}"

ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
if PGPASSWORD="$DB_OWNER_PASSWORD" "$PGBIN/psql" -h 127.0.0.1 -p "$DB_PORT" \
     -U hbh_owner -d hbh -v ON_ERROR_STOP=1 -tAc "SELECT hbh.run_maintenance();" >/dev/null 2>&1
then
  echo "$ts maintenance ok"
else
  echo "$ts maintenance FAILED - see hbh.maintenance_runs"
fi
