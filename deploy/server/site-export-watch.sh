#!/usr/bin/env bash
# =====================================================================
# Run the site export whenever the console's content actually changes.
#
#   bash deploy/server/site-export-watch.sh start|stop|status|logs|once
#
# WHY THIS EXISTS
#
# The console saves a row and marks it "منشور", and nothing reaches a
# visitor until a human runs scripts/site-export.sh in a terminal. The
# screen says published; the site says last week. That gap is invisible
# from both ends - no error, no warning, nothing in the console to show
# how far behind the file is. The owner read it, reasonably, as "the
# database isn't feeding the site at all".
#
# WHAT IT COMPARES, AND WHY NOT TIMESTAMPS
#
# The obvious design polls max(updated_at) against generatedAt. It is
# wrong in both directions: a DRAFT edit moves updated_at without
# changing a byte of output, so the file is rewritten for nothing; and
# any clock skew between this host and the database turns the comparison
# into a coin toss.
#
# So it compares the OUTPUT. `site-export.sh --check` renders what the
# file would contain and writes nothing; strip the timestamp from both
# sides and a difference is, exactly, a difference a visitor would see.
# No skew, no false positives, no guessing which columns matter.
#
# WHAT IT IS NOT
#
# Not a second source of truth, and not a publisher. It runs the same
# script a person would run, with the same identity and the same rules -
# PUBLISHED rows only. It cannot make anything live that the database
# would not have made live.
#
# THE REAL FIX IS STILL THE API. POST /api/v1/site/publish behind
# SITE.PUBLISH, called by the console's own publish button, is the
# version with no polling and no window. This closes the gap today
# without waiting for it, and it retires the moment that endpoint lands.
# =====================================================================
set -uo pipefail

ROOT="${HBH_ROOT:-$HOME/hand-by-hand}"
EXPORT="$ROOT/scripts/site-export.sh"
OUT="$ROOT/site/content.js"
LOG="${HBH_LOG_DIR:-$HOME/weblog}"
PIDF="$LOG/site-export-watch.pid"

# Seconds between checks. Each one is a single read-only query; the
# default is a compromise between "a visitor sees it quickly" and "this
# is not a busy loop against the clinical database".
INTERVAL="${HBH_EXPORT_INTERVAL:-20}"

# Consecutive failures before it gives up. A watcher that retries a
# broken export every twenty seconds for a week writes a gigabyte of
# identical errors and still has not told anybody.
MAX_FAILS="${HBH_EXPORT_MAX_FAILS:-10}"

running() { [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; }

# The timestamp is the one field that changes on every render, so it is
# removed from both sides before comparing. Everything else IS the
# content.
strip_stamp() { grep -v '"generatedAt"' "$1" 2>/dev/null; }

# One pass. Returns 0 when nothing needed doing, 10 when it exported,
# and 1 when the export itself failed - three outcomes, not two, so the
# caller can tell "no change" from "could not look".
export_if_changed() {
  local tmp rc
  tmp="$(mktemp)"

  if ! bash "$EXPORT" --check >"$tmp" 2>/dev/null; then
    rm -f "$tmp"
    return 1
  fi

  # An empty render is a failure wearing a success code - the database
  # was unreachable, or the query returned nothing at all. Writing it
  # would blank every managed string on the site.
  if [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    return 1
  fi

  if [ -f "$OUT" ] && diff -q <(strip_stamp "$tmp") <(strip_stamp "$OUT") >/dev/null 2>&1; then
    rm -f "$tmp"
    return 0
  fi

  rm -f "$tmp"
  bash "$EXPORT" >/dev/null 2>&1
  rc=$?
  [ $rc -eq 0 ] && return 10
  return 1
}

loop() {
  local fails=0 rc
  while true; do
    export_if_changed
    rc=$?
    if [ $rc -eq 10 ]; then
      echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ')  exported - the console had changes"
      fails=0
    elif [ $rc -eq 1 ]; then
      fails=$((fails + 1))
      echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ')  export FAILED ($fails/$MAX_FAILS)" >&2
      if [ "$fails" -ge "$MAX_FAILS" ]; then
        echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ')  giving up after $fails failures - the site is now" >&2
        echo "    serving whatever content.js last held. Run the export by hand to see why:" >&2
        echo "    bash scripts/site-export.sh --check" >&2
        exit 1
      fi
    else
      fails=0
    fi
    sleep "$INTERVAL"
  done
}

case "${1:-status}" in
  once)
    export_if_changed
    case $? in
      10) echo "exported - there were changes" ;;
       0) echo "no change - content.js already matches the database" ;;
       *) echo "export failed - run: bash scripts/site-export.sh --check" >&2; exit 1 ;;
    esac
    ;;

  start)
    mkdir -p "$LOG"
    if running; then echo "watcher already running (pid $(cat "$PIDF"))"; exit 0; fi
    [ -x "$EXPORT" ] || [ -f "$EXPORT" ] || { echo "no exporter at $EXPORT" >&2; exit 1; }
    nohup bash "$0" __loop >>"$LOG/site-export-watch.log" 2>&1 &
    echo $! > "$PIDF"
    sleep 1
    if running; then
      echo "watcher on (pid $(cat "$PIDF")) - checking every ${INTERVAL}s"
    else
      echo "watcher FAILED:"; tail -10 "$LOG/site-export-watch.log"
      exit 1
    fi
    ;;

  __loop) loop ;;

  stop)
    if running; then kill "$(cat "$PIDF")" 2>/dev/null; echo "watcher stopped"; fi
    rm -f "$PIDF"
    ;;

  status)
    if running; then
      echo "watcher running (pid $(cat "$PIDF")) - every ${INTERVAL}s"
    else
      echo "watcher NOT running - the console can publish and the site will not change"
    fi
    [ -f "$OUT" ] && echo "  content.js: $(grep -o '\"generatedAt\": \"[^\"]*\"' "$OUT" | head -1)"
    ;;

  logs) tail -n "${2:-30}" "$LOG/site-export-watch.log" ;;

  *) echo "usage: $0 start|stop|status|logs [lines]|once"; exit 1 ;;
esac
