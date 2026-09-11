#!/usr/bin/env bash
# Put the portal and the console on the domain.
#
# THE OWNER'S DECISION, 2026-09-09, made twice and with the reason
# given: nothing has launched, the database holds fixtures only, and
# this is a testing period.
#
# WHAT IS BEING ACCEPTED. portal.hbhskills.com serves a sign-in whose
# OTP_ECHO returns the login code in the response body, so anyone who
# knows a mobile number that exists in this database can sign in as that
# guardian. ops.hbhskills.com serves a console whose three accounts share
# one development password. Both are true the moment the hostname
# resolves, and neither is hidden by the name being new - certificates
# are published in transparency logs as they are issued.
#
# WHAT MUST CHANGE BEFORE A REAL FAMILY EXISTS IN THIS DATABASE:
#   * an SMS gateway, then OTP_ECHO=false and APP_ENV=production
#     (the service refuses to start otherwise - config.go)
#   * a real password per staff member (0068-0070 added the machinery)
# Until both are done, this deployment is for fixtures.
set -uo pipefail
CF="$HOME/bin/cloudflared"
NAME=hbh-site
CFG="$HOME/.cloudflared/config.yml"
UUID=$("$CF" tunnel list 2>/dev/null | awk -v n="$NAME" '$2==n {print $1}' | head -1)
[ -n "$UUID" ] || { echo "no tunnel"; exit 1; }

echo "=== origins must be up first ==="
for p in 8091 8092 8093 8094; do
  c=$(curl -s -o /dev/null -m 8 -w '%{http_code}' "http://127.0.0.1:$p/")
  printf '  %s -> %s\n' "$p" "$c"
  [ "$c" = 200 ] || { echo "  origin $p is not serving; stopping"; exit 1; }
done

cat > "$CFG" <<YAML
tunnel: $UUID
credentials-file: $HOME/.cloudflared/$UUID.json

ingress:
  # Public site - no API at all.
  - hostname: hbhskills.com
    service: http://127.0.0.1:8093
  - hostname: www.hbhskills.com
    service: http://127.0.0.1:8093

  # Enrolment only - one allowed API call, sign-in refused at the origin.
  - hostname: apply.hbhskills.com
    service: http://127.0.0.1:8094

  # Parent portal and staff console. These carry the WHOLE API, sign-in
  # included. See the header of this file for what that means today and
  # what has to be true before a real family is in the database.
  - hostname: portal.hbhskills.com
    service: http://127.0.0.1:8091
  - hostname: ops.hbhskills.com
    service: http://127.0.0.1:8092

  - service: http_status:404
YAML
chmod 600 "$CFG"
"$CF" tunnel ingress validate 2>&1 | tail -2

echo
echo "=== dns ==="
for h in portal.hbhskills.com ops.hbhskills.com; do
  printf '  %-26s ' "$h"
  "$CF" tunnel route dns --overwrite-dns "$NAME" "$h" 2>&1 | tail -1 | sed 's/.*INF //'
done

echo
echo "=== reload ==="
for p in $(pgrep -f "tunnel --no-autoupdate run $NAME" 2>/dev/null); do kill "$p" 2>/dev/null; done
sleep 3
setsid "$CF" tunnel --no-autoupdate run "$NAME" </dev/null >>"$HOME/tunnellog/$NAME.log" 2>&1 &
sleep 12
pgrep -af "run $NAME" >/dev/null && echo "  tunnel up" || echo "  TUNNEL DOWN"
