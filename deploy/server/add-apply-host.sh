#!/usr/bin/env bash
# Add apply.hbhskills.com to the tunnel: the enrolment form, and nothing
# else. The origin on 8094 carries exactly one API call; see the header
# of web.native.mjs for why that list is an allowlist.
set -uo pipefail
CF="$HOME/bin/cloudflared"
NAME=hbh-site
CFG="$HOME/.cloudflared/config.yml"
UUID=$("$CF" tunnel list 2>/dev/null | awk -v n="$NAME" '$2==n {print $1}' | head -1)
[ -n "$UUID" ] || { echo "no tunnel"; exit 1; }

cat > "$CFG" <<YAML
tunnel: $UUID
credentials-file: $HOME/.cloudflared/$UUID.json

ingress:
  # The public site. No API at all.
  - hostname: hbhskills.com
    service: http://127.0.0.1:8093
  - hostname: www.hbhskills.com
    service: http://127.0.0.1:8093

  # The enrolment form only. Its origin refuses every API path except
  # POST /api/v1/enrolments, so sign-in is not reachable here even
  # though this serves the same Angular bundle as the portal.
  - hostname: apply.hbhskills.com
    service: http://127.0.0.1:8094

  # The parent portal (8091) and the staff console (8092) are NOT here.
  # OTP_ECHO returns the login code in the response body, and the staff
  # accounts still carry the development password. Either one published
  # on a name a stranger can guess is an account handed over.
  - service: http_status:404
YAML
chmod 600 "$CFG"
"$CF" tunnel ingress validate 2>&1 | tail -2

echo
echo "=== dns ==="
"$CF" tunnel route dns --overwrite-dns "$NAME" apply.hbhskills.com 2>&1 | tail -2

echo
echo "=== reload the tunnel so the new ingress takes ==="
for p in $(pgrep -f "tunnel --no-autoupdate run $NAME" 2>/dev/null); do kill "$p" 2>/dev/null; done
sleep 3
setsid "$CF" tunnel --no-autoupdate run "$NAME" </dev/null >>"$HOME/tunnellog/$NAME.log" 2>&1 &
sleep 10
pgrep -af "run $NAME" | head -1 | sed 's/^/  /'
tail -30 "$HOME/tunnellog/$NAME.log" | grep -c 'Registered tunnel connection' | sed 's/^/  connections: /'
