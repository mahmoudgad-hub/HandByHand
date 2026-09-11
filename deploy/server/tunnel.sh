#!/usr/bin/env bash
# =====================================================================
# Public HTTPS without root, through Cloudflare quick tunnels.
#
#   bash deploy/server/tunnel.sh start|stop|status|urls
#
# WHY THIS EXISTS
# A certificate a browser trusts requires proving control of a name on
# port 80 or 443. Both belong to the nginx that only root configures, so
# this account cannot obtain one. Cloudflare terminates TLS on its own
# certificate and forwards to a local port over an outbound connection,
# which needs no inbound port and no root at all.
#
# WHAT IT COSTS, PLAINLY
#   * Every request and response passes through Cloudflare in the clear
#     at their edge. For fixture data that is a fair trade; for a real
#     child's record it is a decision somebody has to make on purpose.
#   * A quick tunnel's hostname is random and CHANGES EVERY START. Any
#     link written down - including the site's own link to the portal -
#     is stale the next time this runs. That is why this script rewrites
#     site/config.js itself rather than leaving it to be remembered.
#   * Anyone with the URL reaches the app. The tunnel is encryption and
#     a hostname, not an access control.
#
# The apps stay bound to 127.0.0.1. The tunnel is then the only way in,
# which is strictly less exposed than publishing the ports themselves.
# =====================================================================
set -uo pipefail

ROOT="$HOME/hand-by-hand"
CF="$HOME/bin/cloudflared"
LOG="$HOME/tunnellog"
URLS="$LOG/urls.txt"

# name:port - the three surfaces, each its own tunnel and its own URL.
targets="site:8093 portal:8091 ops:8092"

pidf() { echo "$LOG/$1.pid"; }
running() { local f; f=$(pidf "$1"); [ -f "$f" ] && kill -0 "$(cat "$f")" 2>/dev/null; }

start_one() {
  local name="$1" port="$2"
  if running "$name"; then echo "$name tunnel already up"; return 0; fi
  : > "$LOG/$name.log"
  nohup "$CF" tunnel --no-autoupdate --url "http://127.0.0.1:$port" \
    >>"$LOG/$name.log" 2>&1 &
  echo $! > "$(pidf "$name")"

  # The hostname is only knowable from the log, and it appears a second
  # or two after the process does. Waiting for the pid alone would print
  # a tunnel that has no address yet.
  local url=""
  for _ in $(seq 1 30); do
    url=$(grep -ohE 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG/$name.log" | head -1)
    [ -n "$url" ] && break
    sleep 1
  done
  if [ -z "$url" ]; then
    echo "$name: no URL after 30s. Last lines:"
    tail -5 "$LOG/$name.log"
    return 1
  fi
  printf '%s %s\n' "$name" "$url" >> "$URLS"
  printf '  %-7s %s\n' "$name" "$url"
}

start() {
  [ -x "$CF" ] || { echo "no cloudflared at $CF"; exit 1; }
  mkdir -p "$LOG"; : > "$URLS"

  echo "=== the apps must be listening locally first ==="
  for t in $targets; do
    p="${t##*:}"
    ss -tlnH | grep -q ":$p " && echo "  ok   127.0.0.1:$p" \
      || { echo "  DOWN 127.0.0.1:$p - start it with web.native.sh"; exit 1; }
  done

  echo
  echo "=== tunnels ==="
  for t in $targets; do start_one "${t%%:*}" "${t##*:}" || exit 1; done

  # The site links to the portal by absolute origin, and that origin has
  # just changed. Rewriting it here is not a convenience: a link left
  # pointing at the previous run is a dead button on a public page, and
  # nothing would report it.
  local portal
  portal=$(awk '$1=="portal"{print $2}' "$URLS")
  if [ -n "$portal" ]; then
    echo
    echo "=== pointing the site at this run's portal ==="
    sed -i "s|portalBaseUrl: '[^']*'|portalBaseUrl: '$portal'|" "$ROOT/site/config.js"
    grep -n "portalBaseUrl:" "$ROOT/site/config.js" | sed 's/^/  /'
    # The site serves config.js from disk on each request, so no restart.
  fi

  echo
  echo "Open these:"
  awk '{printf "  %-7s %s\n", $1, $2}' "$URLS"
}

stop() {
  for t in $targets; do
    name="${t%%:*}"; f=$(pidf "$name")
    if running "$name"; then kill "$(cat "$f")" 2>/dev/null; echo "$name tunnel stopped"; fi
    rm -f "$f"
  done
  : > "$URLS" 2>/dev/null
}

case "${1:-status}" in
  start) start ;;
  stop)  stop ;;
  urls)  [ -s "$URLS" ] && awk '{printf "%-7s %s\n", $1, $2}' "$URLS" || echo "no tunnels running" ;;
  status)
    for t in $targets; do
      name="${t%%:*}"
      running "$name" && echo "$name  up" || echo "$name  down"
    done
    [ -s "$URLS" ] && awk '{printf "  %-7s %s\n", $1, $2}' "$URLS"
    ;;
  *) echo "usage: $0 start|stop|status|urls"; exit 1 ;;
esac
