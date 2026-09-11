#!/usr/bin/env bash
# Start, stop and inspect the two front ends on a host without nginx.
#
#   bash deploy/server/web.native.sh start|stop|status|logs
#
# portal -> 8091, ops -> 8092, both loopback only, both proxying /api
# to the service on 8090 so the page and its API share one origin.
set -uo pipefail

ROOT="$HOME/hand-by-hand"
SRV="$ROOT/deploy/server/web.native.mjs"
LOG="$HOME/weblog"
set -a; . "$ROOT/.env"; set +a
API_PORT="${API_PORT:-8090}"

# name : loopback http port : public https port : document root
#
# The two Angular apps are served from their build output; the public
# site is plain HTML and is served from its source directory, because
# there is nothing to build - that was the point of writing it without
# a framework.
# The fifth field says whether unknown paths belong to a client-side
# router. The site has real pages and must answer 404 for what is not
# there, or a missing asset comes back as the homepage with status 200.
apps="portal:8091:8443:web/dist/portal/browser:spa ops:8092:8444:web/dist/ops/browser:spa site:8093:8445:site:static"
TLS_DIR="${HBH_TLS_DIR:-$HOME/tls}"

# Publishing is opt-in per start, never a stored setting: the variable
# has to be on the command that starts it. Restarting without it takes
# the site off the internet, which is the direction a mistake should go.
#
#   HBH_PUBLIC=1        https on 8443/8444, certificate required
#   HBH_PUBLIC_HTTP=1   plain http on 8091/8092, nothing encrypted
PUBLIC="${HBH_PUBLIC:-0}"
PUBLIC_HTTP="${HBH_PUBLIC_HTTP:-0}"

pidf() { echo "$LOG/$1.pid"; }
running() { local f; f=$(pidf "$1"); [ -f "$f" ] && kill -0 "$(cat "$f")" 2>/dev/null; }

start() {
  mkdir -p "$LOG"
  for a in $apps; do
    local name port tls docroot mode
    name=$(echo "$a" | cut -d: -f1)
    port=$(echo "$a" | cut -d: -f2)
    tls=$(echo  "$a" | cut -d: -f3)
    docroot=$(echo "$a" | cut -d: -f4)
    mode=$(echo "$a" | cut -d: -f5)
    if running "$name"; then echo "$name already running"; continue; fi
    local dist="$ROOT/$docroot"
    [ -d "$dist" ] || { echo "$name: nothing at $dist"; continue; }
    if [ "$PUBLIC" = 1 ] && [ ! -r "$TLS_DIR/cert.pem" ]; then
      echo "$name: HBH_PUBLIC=1 but no certificate in $TLS_DIR - refusing to publish in the clear"
      continue
    fi
    HBH_PUBLIC="$PUBLIC" HBH_PUBLIC_HTTP="$PUBLIC_HTTP" \
      nohup node "$SRV" "$dist" "$port" "$API_PORT" "$tls" "$TLS_DIR" "$mode" >>"$LOG/$name.log" 2>&1 &
    echo $! > "$(pidf "$name")"
    sleep 1
    if running "$name"; then
      echo "$name on 127.0.0.1:$port (pid $(cat "$(pidf "$name")"))"
    else
      echo "$name FAILED:"; tail -10 "$LOG/$name.log"
    fi
  done
}

stop() {
  for a in $apps; do
    local name="${a%%:*}" f
    f=$(pidf "$name")
    if running "$name"; then kill "$(cat "$f")" 2>/dev/null; echo "$name stopped"; fi
    rm -f "$f"
  done
}

case "${1:-status}" in
  start) start ;;
  stop)  stop ;;
  restart) stop; sleep 1; start ;;
  status)
    for a in $apps; do
      name=$(echo "$a" | cut -d: -f1)
      port=$(echo "$a" | cut -d: -f2)
      tls=$(echo  "$a" | cut -d: -f3)
      if running "$name"; then
        code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/")
        bind=$(ss -tlnH | awk -v p=":$port" '$4 ~ p {print $4}' | head -1)
        printf '%-7s running   http %s -> %s' "$name" "${bind:-?}" "$code"
        # -k because the certificate is self-signed; this asks whether
        # the listener answers, not whether a browser would trust it.
        tcode=$(curl -sk -o /dev/null -w '%{http_code}' "https://127.0.0.1:$tls/" 2>/dev/null)
        if [ -n "$tcode" ] && [ "$tcode" != 000 ]; then
          printf '   https :%s -> %s  PUBLIC\n' "$tls" "$tcode"
        else
          printf '   https :%s not listening\n' "$tls"
        fi
      else
        echo "$name  not running"
      fi
    done
    echo
    # Single quotes: $4 belongs to awk, and in double quotes the shell
    # would have eaten it and printed every column instead.
    ss -tlnH | awk '{print $4}' | grep -E ':(8091|8092|8093|8443|8444|8445)$' | sort || echo "(nothing listening)"
    ;;
  logs) tail -n "${3:-40}" "$LOG/${2:-portal}.log" ;;
  *) echo "usage: $0 start|stop|restart|status|logs [portal|ops]"; exit 1 ;;
esac
