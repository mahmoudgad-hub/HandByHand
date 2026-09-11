#!/usr/bin/env bash
# =====================================================================
# hbhskills.com -> the public site, over a named Cloudflare tunnel.
#
# WHY A NAMED TUNNEL AND NOT THE QUICK ONES
# A quick tunnel's hostname is random and changes every restart, which is
# fine for showing somebody a screen and useless for a domain. A named
# tunnel keeps its address, and Cloudflare terminates TLS for it - so the
# site gets a real certificate on 443 without root, without certbot and
# without touching the nginx that belongs to the other ten projects here.
#
# WHAT THE INGRESS DOES, AND WHAT IT DELIBERATELY DOES NOT
# Two hostnames reach one origin: 127.0.0.1:8093, the site. Nothing else
# is listed, and the last rule returns 404 for everything that is not
# those two names. The portal on 8091 and the console on 8092 are NOT
# here and must not be added: OTP_ECHO still returns the login code in
# the response body, so publishing either of them hands a stranger any
# parent's account. That condition is written in hbh.nginx.conf and it
# has not changed.
# =====================================================================
set -uo pipefail

CF="$HOME/bin/cloudflared"
NAME=hbh-site
DOMAIN=hbhskills.com
ORIGIN=http://127.0.0.1:8093
CFG="$HOME/.cloudflared/config.yml"
LOG="$HOME/tunnellog"

[ -x "$CF" ] || { echo "no cloudflared at $CF"; exit 1; }
[ -r "$HOME/.cloudflared/cert.pem" ] || { echo "not authorised - run: $CF tunnel login"; exit 1; }

echo "=== the origin must be up before anything points at it ==="
code=$(curl -s -o /dev/null -w '%{http_code}' "$ORIGIN/")
echo "  $ORIGIN -> HTTP $code"
[ "$code" = 200 ] || { echo "  site is not serving; refusing to publish a dead origin"; exit 1; }

echo
echo "=== tunnel ==="
if "$CF" tunnel list 2>/dev/null | grep -q "[[:space:]]$NAME[[:space:]]"; then
  echo "  '$NAME' already exists"
else
  "$CF" tunnel create "$NAME" 2>&1 | tail -2
fi
UUID=$("$CF" tunnel list 2>/dev/null | awk -v n="$NAME" '$2==n {print $1}' | head -1)
[ -n "$UUID" ] || { echo "  could not read the tunnel id"; exit 1; }
echo "  id: $UUID"

echo
echo "=== config ==="
cat > "$CFG" <<YAML
tunnel: $UUID
credentials-file: $HOME/.cloudflared/$UUID.json

# Only the public site. Adding the portal or the console here would put
# the clinical record on the open internet - see the header of this file
# and deploy/server/hbh.nginx.conf.
ingress:
  - hostname: $DOMAIN
    service: $ORIGIN
  - hostname: www.$DOMAIN
    service: $ORIGIN
  # Anything else that reaches this tunnel is refused rather than
  # falling through to whatever happens to be listening.
  - service: http_status:404
YAML
chmod 600 "$CFG"
"$CF" tunnel ingress validate 2>&1 | tail -2

echo
echo "=== dns ==="
for h in "$DOMAIN" "www.$DOMAIN"; do
  out=$("$CF" tunnel route dns "$NAME" "$h" 2>&1)
  case "$out" in
    *"already exists"*|*"successfully"*|*"Added"*) echo "  $h  ok" ;;
    *) echo "  $h  $out" ;;
  esac
done

echo
echo "=== run it ==="
mkdir -p "$LOG"
for p in $(pgrep -f "cloudflared tunnel run $NAME" 2>/dev/null); do kill "$p" 2>/dev/null; done
sleep 1
nohup "$CF" tunnel --no-autoupdate run "$NAME" >>"$LOG/$NAME.log" 2>&1 &
echo "  pid $!"
sleep 8
grep -oE 'Registered tunnel connection|ERR |error' "$LOG/$NAME.log" | tail -3
