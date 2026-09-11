#!/usr/bin/env bash
# =====================================================================
# The whole stack on a host where this account has no root and no
# docker: database, API, both front ends.
#
#   bash deploy/server/stack.native.sh start|stop|status
#
# The database, the API, the portal and the console listen on
# 127.0.0.1 only. The way in is a tunnel:
#
#   ssh -L 8091:127.0.0.1:8091 -L 8092:127.0.0.1:8092 gad
#
# The public site on 8093 is the one exception, and the only thing here
# meant to be reachable from outside. It serves static files and has no
# route to the API - see deploy/server/site.native.mjs.
# =====================================================================
set -uo pipefail
ROOT="$HOME/hand-by-hand"
cd "$ROOT" || exit 1

case "${1:-status}" in
  start)
    echo "=== database ==="
    HBH_DB_MODE=native bash scripts/db.sh up || exit 1
    echo
    echo "=== api ==="
    bash deploy/server/api.native.sh start || exit 1
    echo
    echo "=== front ends ==="
    bash deploy/server/web.native.sh start
    echo
    echo "=== public site ==="
    bash deploy/server/site.native.sh start
    bash deploy/server/site-export-watch.sh start
    ;;
  stop)
    bash deploy/server/site-export-watch.sh stop
    bash deploy/server/site.native.sh stop
    bash deploy/server/web.native.sh stop
    bash deploy/server/api.native.sh stop
    HBH_DB_MODE=native bash scripts/db.sh down
    ;;
  status)
    echo "=== database ==="
    HBH_PG_BIN="$HOME/pgsql/usr/lib/postgresql/17/bin"
    LD_LIBRARY_PATH="$HOME/pgsql/deps" "$HBH_PG_BIN/pg_isready" -h 127.0.0.1 -p 5434 \
      || echo "postgres is down"
    echo
    echo "=== api ==="
    bash deploy/server/api.native.sh status
    echo
    echo "=== front ends ==="
    bash deploy/server/web.native.sh status
    echo
    echo "=== public site ==="
    bash deploy/server/site.native.sh status
    bash deploy/server/site-export-watch.sh status
    echo
    echo "=== maintenance is actually running ==="
    HBH_DB_MODE=native bash scripts/db.sh health 2>/dev/null || echo "could not read health"
    ;;
  *) echo "usage: $0 start|stop|status"; exit 1 ;;
esac
