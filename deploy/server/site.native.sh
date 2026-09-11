#!/usr/bin/env bash
# Start, stop and inspect the public site on a host without nginx.
#
#   bash deploy/server/site.native.sh start|stop|restart|status|logs
#
# site -> 8093 http, 8445 https when a certificate is present.
#
# This one is PUBLIC by default, which is the opposite of every other
# front end here. The reason it is safe to publish is that
# site.native.mjs has no API proxy at all - read the header of that file
# before changing anything here. Nothing under web/site reaches the
# database, the service, or a single row belonging to a family.
#
# Set HBH_SITE_BIND=127.0.0.1 to keep it on loopback while working.
set -uo pipefail

ROOT="$HOME/hand-by-hand"
SRV="$ROOT/deploy/server/site.native.mjs"
DIR="$ROOT/site"
LOG="$HOME/weblog"
PORT="${HBH_SITE_PORT:-8093}"
TLS_PORT="${HBH_SITE_TLS_PORT:-8445}"
TLS_DIR="${HBH_TLS_DIR:-$HOME/tls}"
PIDF="$LOG/site.pid"

running() { [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; }

# ---------------------------------------------------------------------
# THE DEPLOYMENT TEST: ask what must NOT be answered.
#
# `/` returning 200 proves nothing - it was 200 throughout the eleven
# minutes hbhskills.com served /api/v1/auth/otp/request and handed back
# a parent's login code to anyone who knew their mobile number. The site
# looked perfect the whole time. What proves the property is the other
# question: does an API path on this origin return 404?
#
# It lives here, in the file that RUNS, and not only in a comment or in
# hbh.nginx.conf - which is where the rule was written last time, in a
# config that was not the one serving traffic.
#
# Any answer other than 404 is a finding, including 200, 401, 405 and
# 502: a 502 means something IS forwarding, it just could not reach the
# service this second.
# ---------------------------------------------------------------------
check_no_api() {
  local origin="${1:-http://127.0.0.1:$PORT}" bad=0 code p
  for p in /api/v1/auth/otp/request /api/v1/enrolments /api/ /healthz; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$origin$p" 2>/dev/null)
    if [ "$code" = 000 ]; then
      echo "      $p  unreachable - not checked" >&2
      bad=1
    elif [ "$code" != 404 ]; then
      echo "  !!  $origin$p answered $code - expected 404" >&2
      bad=1
    fi
  done

  if [ "$bad" -ne 0 ]; then
    echo "  !!  THIS ORIGIN REACHES THE SERVICE. The public site must not." >&2
    echo "      Check which program is serving it: site.native.mjs has no" >&2
    echo "      proxy; web.native.mjs does, and is for the portal and the" >&2
    echo "      console only." >&2
    return 1
  fi
  echo "      api paths: 404 on all four - no route to the service"
  return 0
}

# check_no_docs asks for the things that live in the folder and are not
# the site.
#
# site/README.md and site/CONTENT-AUDIT.md document the page and sit
# beside it, which is right. They were also SERVED: the static server
# answered any path under its root and fell back to octet-stream for an
# extension it did not know, so both came back 200 to a plain curl.
# Between them they name every table behind the site, the permission
# that gates publishing, the migration numbers, which console screens
# are broken, and which testimonials are held back for want of a
# family's consent.
#
# Nothing linked to them, and that is not a control - README.md is not a
# name anybody has to guess.
#
# THIS ASKS FOR WHAT MUST NOT BE ANSWERED, which is the half of the
# deploy lesson that catches things: `/` returning 200 proves nothing,
# and one of these returning anything but 404 proves everything. A
# directory listing is checked too, because that is the other way a
# folder tells a stranger what is in it.
check_no_docs() {
  local origin="${1:-http://127.0.0.1:$PORT}" bad=0 code p
  for p in /README.md /CONTENT-AUDIT.md /content.json /package.json /.env /assets/; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$origin$p" 2>/dev/null)
    if [ "$code" = 000 ]; then
      echo "      $p  unreachable - not checked" >&2
      bad=1
    elif [ "$code" != 404 ]; then
      echo "  !!  $origin$p answered $code - expected 404" >&2
      bad=1
    fi
  done

  if [ "$bad" -ne 0 ]; then
    echo "  !!  THIS ORIGIN PUBLISHES ITS OWN NOTES. Only the file types in" >&2
    echo "      TYPES (site.native.mjs) are servable; anything else must be" >&2
    echo "      a 404. A document that explains the system to whoever asks" >&2
    echo "      for it is a map, and it is handed out with a 200." >&2
    return 1
  fi
  echo "      notes and configs: 404 on all six - the folder serves the site only"
  return 0
}

start() {
  mkdir -p "$LOG"
  if running; then echo "site already running (pid $(cat "$PIDF"))"; return; fi
  [ -f "$DIR/index.html" ] || { echo "site: no index.html in $DIR"; return 1; }

  # A deployment that never filled in config.js links its main button to
  # nowhere. The page handles that on its own - the buttons fall back to
  # the contact section - but it is worth saying once at start, because
  # the page looks entirely finished in that state.
  if ! grep -qE "portalBaseUrl:[[:space:]]*'[^']+'" "$DIR/config.js" 2>/dev/null; then
    echo "site: portalBaseUrl is empty in site/config.js"
    echo "      the apply and sign-in buttons will point at the contact section"
  fi

  local tls=0
  [ -r "$TLS_DIR/cert.pem" ] && tls="$TLS_PORT"

  nohup node "$SRV" "$DIR" "$PORT" "$tls" "$TLS_DIR" >>"$LOG/site.log" 2>&1 &
  echo $! > "$PIDF"
  sleep 1
  if running; then
    echo "site on ${HBH_SITE_BIND:-0.0.0.0}:$PORT (pid $(cat "$PIDF"))"
    [ "$tls" != 0 ] && echo "     https on 0.0.0.0:$TLS_PORT"
  else
    echo "site FAILED:"; tail -10 "$LOG/site.log"
  fi
}

stop() {
  if running; then kill "$(cat "$PIDF")" 2>/dev/null; echo "site stopped"; fi
  rm -f "$PIDF"
}

case "${1:-status}" in
  start) start ;;
  stop) stop ;;
  restart) stop; sleep 1; start ;;
  status)
    if running; then
      code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/")
      bind=$(ss -tlnH | awk -v p=":$PORT" '$4 ~ p {print $4}' | head -1)
      echo "site  running   http ${bind:-?} -> $code"
      check_no_api "http://127.0.0.1:$PORT"
      check_no_docs "http://127.0.0.1:$PORT"
    else
      echo "site  not running"
    fi
    ;;

  # The deployment test, on demand and against any origin:
  #
  #   bash deploy/server/site.native.sh audit https://hbhskills.com
  #
  # BOTH checks run even when the first fails, and the exit code is the
  # worse of the two. Stopping at the first would report one finding and
  # hide the other, and "fix it and run again" is how a second finding
  # gets discovered a week late.
  audit)
    rc=0
    check_no_api  "${2:-http://127.0.0.1:$PORT}" || rc=1
    check_no_docs "${2:-http://127.0.0.1:$PORT}" || rc=1
    exit "$rc"
    ;;
  logs) tail -n "${2:-40}" "$LOG/site.log" ;;
  *) echo "usage: $0 audit [origin]|start|stop|restart|status|logs [lines]"; exit 1 ;;
esac
