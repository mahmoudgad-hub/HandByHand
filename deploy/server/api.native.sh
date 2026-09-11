#!/usr/bin/env bash
# =====================================================================
# Run hbhd on a host with no docker.
#
#   bash deploy/server/api.native.sh start|stop|status|logs
#
# The binary is static and was built by api/Dockerfile's build stage,
# so go vet and go test ran before it existed.
#
# API_LISTEN IS 127.0.0.1 AND NOT ":8090".
# Under compose the port is published by docker and BIND_ADDR decides
# the interface. There is no docker here: whatever the process binds is
# what the world can reach, and this host answers on a public address.
# ":8090" would put the clinical record on the open internet with one
# character's difference and no warning anywhere.
# =====================================================================
set -uo pipefail

ROOT="$HOME/hand-by-hand"
BIN="$ROOT/deploy/server/hbhd"
LOG="$HOME/apilog"
PIDF="$HOME/apilog/hbhd.pid"

[ -f "$ROOT/.env" ] || { echo "no $ROOT/.env"; exit 1; }
set -a; . "$ROOT/.env"; set +a

DB_PORT="${DB_PORT:-5434}"
API_PORT="${API_PORT:-8090}"

running() {
  [ -f "$PIDF" ] || return 1
  kill -0 "$(cat "$PIDF")" 2>/dev/null
}

start() {
  if running; then echo "already running (pid $(cat "$PIDF"))"; return 0; fi
  [ -x "$BIN" ] || { echo "no executable at $BIN"; exit 1; }
  mkdir -p "$LOG"

  # sslmode=disable is correct for a loopback socket on the same host and
  # wrong for anything else. If this ever points at another machine, it
  # has to change in the same edit.
  export DATABASE_URL="postgres://hbh_app:${DB_APP_PASSWORD}@127.0.0.1:${DB_PORT}/hbh?sslmode=disable"
  export API_LISTEN="127.0.0.1:${API_PORT}"
  export APP_ENV="${APP_ENV:-development}"
  export LOG_LEVEL="${LOG_LEVEL:-info}"
  export CORS_ORIGINS="${CORS_ORIGINS:-http://localhost:8091}"
  export OTP_ECHO="${OTP_ECHO:-true}"
  export TRUST_PROXY="false"
  export AUTH_RATE_PER_MINUTE="${AUTH_RATE_PER_MINUTE:-60}"
  export TZ=UTC

  nohup "$BIN" >>"$LOG/hbhd.log" 2>&1 &
  echo $! > "$PIDF"
  sleep 2

  if ! running; then
    echo "hbhd died on startup. Last lines:"
    tail -20 "$LOG/hbhd.log"
    rm -f "$PIDF"
    exit 1
  fi
  echo "started (pid $(cat "$PIDF"))"

  # A pid alone proves the process exists, not that it serves. The
  # service checks its database grants at boot and exits if they are
  # wrong; asking /healthz is what distinguishes the two.
  for _ in $(seq 1 15); do
    if curl -fsS "http://127.0.0.1:${API_PORT}/healthz" >/dev/null 2>&1; then
      echo "healthz: $(curl -fsS "http://127.0.0.1:${API_PORT}/healthz")"
      return 0
    fi
    sleep 1
  done
  echo "process is up but /healthz never answered. Last lines:"
  tail -20 "$LOG/hbhd.log"
  return 1
}

stop() {
  if ! running; then echo "not running"; rm -f "$PIDF"; return 0; fi
  kill "$(cat "$PIDF")" && sleep 1
  running && kill -9 "$(cat "$PIDF")" 2>/dev/null
  rm -f "$PIDF"
  echo "stopped"
}

case "${1:-status}" in
  start)  start ;;
  stop)   stop ;;
  restart) stop; start ;;
  status)
    if running; then
      echo "running (pid $(cat "$PIDF"))"
      curl -fsS "http://127.0.0.1:${API_PORT}/healthz" && echo
    else
      echo "not running"
    fi
    ss -tlnH | grep ":${API_PORT}" || echo "(nothing listening on ${API_PORT})"
    ;;
  logs)   tail -n "${2:-60}" "$LOG/hbhd.log" ;;
  *)      echo "usage: $0 start|stop|restart|status|logs [n]"; exit 1 ;;
esac
