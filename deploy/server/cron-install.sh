#!/usr/bin/env bash
# Install this account's crontab: bring the stack back after a reboot,
# and run the periodic maintenance that the compose file gives to a
# looping container.
#
# A user crontab needs no root. It also does NOT need lingering: cron
# is a system daemon and runs these regardless of whether anyone is
# logged in - which is the difference between this and a systemd user
# unit, and the reason for choosing it here.
set -uo pipefail

ROOT="$HOME/hand-by-hand"
set -a; . "$ROOT/.env"; set +a
INTERVAL="${MAINTENANCE_INTERVAL_SECONDS:-3600}"

# Cron's finest granularity is a minute. Anything under that becomes
# "every minute"; anything else is rounded to whole minutes so the
# schedule cannot silently differ from what .env asks for.
mins=$(( INTERVAL / 60 ))
[ "$mins" -lt 1 ] && mins=1
if [ "$mins" -ge 60 ]; then
  hours=$(( mins / 60 ))
  [ "$hours" -gt 23 ] && hours=23
  SCHED="0 */$hours * * *"
  human="every $hours hour(s)"
else
  SCHED="*/$mins * * * *"
  human="every $mins minute(s)"
fi

echo "MAINTENANCE_INTERVAL_SECONDS=$INTERVAL -> $human"

existing=$(crontab -l 2>/dev/null | grep -v 'hand-by-hand/deploy/server' || true)

{
  [ -n "$existing" ] && echo "$existing"
  cat <<CRON
# ---- Hand By Hand ----------------------------------------------------
# Written by deploy/server/cron-install.sh. Remove these three lines to
# uninstall; nothing else on this account depends on them.
#
# The stack binds only 127.0.0.1, so coming back after a reboot exposes
# nothing new - it restores what the tunnel reaches.
@reboot sleep 30 && bash \$HOME/hand-by-hand/deploy/server/stack.native.sh start >> \$HOME/cronlog.txt 2>&1
$SCHED bash \$HOME/hand-by-hand/deploy/server/maintenance.native.sh >> \$HOME/cronlog.txt 2>&1
CRON
} | crontab -

echo
echo "=== installed ==="
crontab -l | grep -A4 'Hand By Hand'
