#!/usr/bin/env bash
# Start the named tunnel properly detached.
#
# nohup alone was not enough: cloudflared kept the ssh channel's stdout
# open, so the ssh call hung until it timed out, and when that channel
# finally went the tunnel went with it. setsid puts it in its own
# session and all three streams are closed off, so it belongs to no
# terminal and outlives every login.
set -uo pipefail
CF="$HOME/bin/cloudflared"
NAME=hbh-site
LOG="$HOME/tunnellog"
mkdir -p "$LOG"

for p in $(pgrep -f "tunnel --no-autoupdate run $NAME" 2>/dev/null); do kill "$p" 2>/dev/null; done
sleep 2

setsid "$CF" tunnel --no-autoupdate run "$NAME" </dev/null >>"$LOG/$NAME.log" 2>&1 &
disown 2>/dev/null || true
sleep 10

echo "=== processes ==="
pgrep -af "run $NAME" | sed 's/^/  /' | head -3

echo
echo "=== connections registered ==="
tail -40 "$LOG/$NAME.log" | grep -c 'Registered tunnel connection'

echo
echo "=== origin still up ==="
curl -s -o /dev/null -w '  127.0.0.1:8093  HTTP %{http_code}\n' http://127.0.0.1:8093/
