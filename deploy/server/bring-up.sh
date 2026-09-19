#!/usr/bin/env bash
# =====================================================================
# Bring the stack up on this host, from nothing to answering.
#
#   bash ~/hand-by-hand/deploy/server/bring-up.sh
#
# It stops at the first failure and says which step failed, because a
# migration that half-applied and a suite that was never reached read
# identically in a log that scrolled past.
# =====================================================================
set -uo pipefail

ROOT="$HOME/hand-by-hand"
cd "$ROOT" || { echo "no $ROOT"; exit 1; }

step=0
run() {
  step=$((step + 1))
  local label="$1"; shift
  echo
  echo "----- [$step] $label -----"
  if "$@"; then
    echo "[$step] OK"
  else
    local rc=$?
    echo "[$step] FAILED ($label) with exit $rc" >&2
    exit "$rc"
  fi
}

# The whole point of this script is the step below. Without membership
# of the docker group every command here fails with a permission error
# on the socket, and the failure reads like a broken compose file.
if ! docker ps >/dev/null 2>&1; then
  echo "docker is not reachable as $(whoami)." >&2
  echo "A one-time root action is still missing:" >&2
  echo "    usermod -aG docker collab" >&2
  echo "    chmod 711 /home/collab" >&2
  echo "If it was just run, open a NEW ssh session - group membership" >&2
  echo "is granted at login and this one predates it." >&2
  exit 1
fi

run "database container"        bash scripts/db.sh up
run "migrations"                bash scripts/db.sh migrate
run "schema-wide conventions"   bash scripts/db.sh verify 00
run "build the API image"       bash scripts/api.sh build
run "start the API"             bash scripts/api.sh up

echo
echo "----- health -----"
curl -fsS "http://127.0.0.1:${API_PORT:-8090}/healthz" && echo

echo
echo "----- what is listening -----"
ss -tlnH | grep -E ':(5434|8090|8091|8092)' || echo "(nothing yet)"

cat <<'DONE'

Up. Reach it from your machine with:

    ssh -L 8091:127.0.0.1:8091 -L 8092:127.0.0.1:8092 gad

    http://localhost:8091   parent portal
    http://localhost:8092   operations console

Nothing is published to the internet: BIND_ADDR is 127.0.0.1 and the
nginx site listens on loopback only. That is deliberate while OTP_ECHO
returns the login code in the response body.
DONE
