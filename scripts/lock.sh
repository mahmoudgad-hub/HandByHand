# shellcheck shell=bash
# =====================================================================
# Hand By Hand (new) - the machine-wide lock, shared by api.sh and db.sh
#
# Sourced, never run. One copy on purpose: the lock is only a lock if
# every writer that can move the ground under a run takes the SAME one,
# and two copies of this file would drift the way two copies of a rule
# always do. It moved here from api.sh on 2026-09-12, when db.sh migrate
# started taking it.
#
# Needs nothing from its caller. Safe under `set -euo pipefail`.
# =====================================================================
# =====================================================================
# THE LOCK
#
# One machine, one shared database, one API container, and several
# sessions. Everything below exists because that is true.
#
# WHAT IT COST, IN ONE NIGHT:
#   - a full run split across two IMAGES: a peer rebuilt while it was
#     measuring, so early suites tested one binary and late ones another,
#     and the single number at the bottom described neither. Two sessions
#     reasoned from it.
#   - a full run split across two SCHEMAS: 0125 landed between suite a6
#     and a7.
#   - 97 failures in one suite, not one of them a defect: a third session
#     restarted the service in the middle of a login.
#   - and half an hour of a peer's time, stopped on a compile error that
#     had been fixed twenty minutes earlier.
#
# The pin in cmd_verify DETECTS all of that and refuses to print a
# verdict. This PREVENTS it. Detection was worth having and is still
# there, but a run that has to be thrown away has already cost its twenty
# minutes.
#
# AND FOR ONE MORE DAY IT DID NOT PREVENT THE COMMONEST MOVER. The lock
# lived in api.sh alone, so `db.sh migrate` walked straight past it: of
# the migrations that landed on 2026-09-11/12, one voided a run overnight
# and 0129 voided a full one in its final suite. The pin caught both and
# prevented neither. migrate now takes this lock - but only when it has
# something to apply. See cmd_migrate in db.sh for why a no-op must not
# wait.
#
# WHAT IT STILL DOES NOT COVER, said plainly so nobody reads more into it:
# `db.sh verify` - the DB suites - does not take it. Their fixtures insert
# and delete rows on shared tables every few seconds, and on 2026-09-12
# one of those rows sat inside an API suite's read for twenty seconds.
# That is fixed at the root (a suite counts its own fixture, not the
# table), not with a lock that would serialise two half-hour runs.
#
# WHY A DIRECTORY AND NOT A FILE. `mkdir` either creates or fails, in one
# atomic step the kernel arbitrates. `[ -e ] && touch` is two steps with a
# gap, and the gap is precisely the case a lock exists for.
#
# WHY NOT IN THE PROJECT TREE. It is under "سطح المكتب", redirected into
# OneDrive. A lock file there would be SYNCHRONISED - replicated, delayed,
# possibly conflict-renamed - and a mutual exclusion primitive whose
# writes are eventually consistent is not one. Same reason backups moved
# to ~/hbh-backups.
#
# WHY A HEARTBEAT AND NOT AN AGE. A run legitimately takes twenty
# minutes, so "stale after twenty minutes" cannot tell a long run from a
# dead one, and either blocks the living or steals from them. The holder
# touches a file every 20 seconds; anything whose last breath is older
# than LOCK_STALE is gone, and that answer is right within a minute
# whether the run is one minute long or forty.
#
# WHY A TOKEN. If we break a dead holder's lock and that process later
# wakes and calls release, it must not delete OURS. Release removes the
# directory only when the token inside it is the one we wrote.
# =====================================================================
LOCK_DIR="${HBH_LOCK_DIR:-$HOME/.hbh-locks}/api.lock"
LOCK_STALE=90        # seconds without a heartbeat before a holder is gone
LOCK_WAIT_MAX=2400   # give up waiting after 40 minutes rather than hang

lock_holder_line() {
  [ -r "$LOCK_DIR/meta" ] || { echo 'unknown holder'; return; }
  local who when beat age
  who="$(sed -n '1p' "$LOCK_DIR/meta" 2>/dev/null)"
  when="$(sed -n '2p' "$LOCK_DIR/meta" 2>/dev/null)"
  beat="$(date -r "$LOCK_DIR/beat" +%s 2>/dev/null || echo 0)"
  age=$(( $(date +%s) - beat ))
  echo "${who:-?} since ${when:-?} (last breath ${age}s ago)"
}

# lock_holder_alive: is the process named in the token still running, and
# still one of the scripts that take this lock? No token, no /proc entry,
# or a different program under that pid all answer "no".
lock_holder_alive() {
  local tok pid cmd
  tok="$(cat "$LOCK_DIR/token" 2>/dev/null || true)"
  pid="${tok%%-*}"
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  [ -r "/proc/$pid/cmdline" ] || return 1
  cmd="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
  case "$cmd" in
    *scripts/api.sh*|*scripts/db.sh*|*scripts/lock.sh*) return 0 ;;
  esac
  return 1
}

# lock_still_mine: the token on disk is the one this process wrote. A run
# asks this before every suite: if it ever answers no, somebody took the
# lock while this run was alive, and whatever it measures from here shares
# the container with another run.
lock_still_mine() {
  [ -n "${HBH_LOCK_TOKEN:-}" ] || return 1
  [ "$(cat "$LOCK_DIR/token" 2>/dev/null || true)" = "$HBH_LOCK_TOKEN" ]
}

lock_release() {
  # Only ours. A token mismatch means somebody took over after we were
  # declared dead, and removing their directory would hand the machine
  # to two runs at once - the exact thing this file prevents.
  local tok
  tok="$(cat "$LOCK_DIR/token" 2>/dev/null || true)"
  if [ -n "${HBH_LOCK_TOKEN:-}" ] && [ "$tok" = "$HBH_LOCK_TOKEN" ]; then
    # `|| true` is not decoration. This runs from an EXIT trap under
    # `set -e`, and the last command of an && list is NOT exempt from
    # errexit: a heartbeat that has already gone makes `kill` fail, the
    # trap exits right here, and the rm below never runs - leaving the
    # lock to the stale rule instead of freeing it now.
    if [ -n "${HBH_LOCK_BEAT_PID:-}" ]; then
      kill "$HBH_LOCK_BEAT_PID" 2>/dev/null || true
    fi
    rm -rf "$LOCK_DIR"
  fi
}

lock_acquire() {
  # Re-entrant: cmd_verify calls cmd_up, and a lock that deadlocks
  # against itself is worse than none.
  [ -n "${HBH_LOCK_TOKEN:-}" ] && return 0

  mkdir -p "$(dirname "$LOCK_DIR")" 2>/dev/null

  local what="${1:-work}" waited=0 announced=0 quiet_alive=0
  while :; do
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      HBH_LOCK_TOKEN="$$-$(date +%s)-$RANDOM"
      export HBH_LOCK_TOKEN
      printf '%s\n%s\n' "${HBH_SESSION_NAME:-a session} ($what, pid $$)" \
                        "$(date '+%H:%M:%S')" > "$LOCK_DIR/meta"
      printf '%s' "$HBH_LOCK_TOKEN" > "$LOCK_DIR/token"
      touch "$LOCK_DIR/beat"

      # The heartbeat, and it watches its OWN holder.
      #
      # `kill -0` is the whole of it: a heartbeat that outlives the run it
      # speaks for makes the lock immortal - the directory keeps breathing
      # with nobody behind it, so the stale rule never fires and every
      # other session waits for a process that no longer exists. That is
      # strictly worse than no lock, because it fails closed and silent.
      #
      # It is not belt-and-braces for the trap. The trap is NOT reliable
      # here: a TERM arriving while the script waits on `docker compose`
      # is handled only after that child returns, and a hard kill never
      # runs it at all. Measured: killing a run left the directory behind.
      # So the trap is the fast path for a clean exit, and this loop plus
      # the stale rule is the one that actually always works - within
      # LOCK_STALE seconds, with no human in the loop.
      local owner=$$
      ( while kill -0 "$owner" 2>/dev/null && [ -d "$LOCK_DIR" ]; do
          touch "$LOCK_DIR/beat" 2>/dev/null; sleep 20
        done ) &
      HBH_LOCK_BEAT_PID=$!
      export HBH_LOCK_BEAT_PID
      trap lock_release EXIT INT TERM
      [ "$announced" = 1 ] && echo "lock: acquired after ${waited}s"
      return 0
    fi

    # Held. Capture first, then judge - a `date -r` on a directory being
    # removed underneath prints nothing, and an empty answer must not
    # read as "fresh".
    local beat age
    beat="$(date -r "$LOCK_DIR/beat" +%s 2>/dev/null || echo 0)"
    age=$(( $(date +%s) - beat ))

    # A SILENT HOLDER IS NOT A DEAD ONE WHEN THE MACHINE SLEPT.
    #
    # 2026-09-12/13: a full run held this lock at 23:26 and the laptop went
    # to sleep. It woke at 11:33:57; the heartbeat was twelve hours old, and
    # a run that had been waiting since 23:22 took over at 11:34:02 - while
    # the first one was alive and carried on from phase 7. Two runs on one
    # container, by the rule written to prevent exactly that. The heartbeat
    # measures silence; sleep silences everything and kills nothing.
    #
    # So age alone never decides. The holder's pid is in its token, and
    # /proc answers for processes of every Git Bash session on this machine
    # (measured: this shell reads another session's /proc/<pid>/cmdline).
    # Alive AND one of our scripts means asleep, not dead - wait, and its
    # own heartbeat resumes within twenty seconds. The script check is what
    # keeps a reused pid after a reboot from holding the lock for ever.
    if [ "$age" -gt "$LOCK_STALE" ] && lock_holder_alive; then
      if [ "${quiet_alive:-0}" = 0 ]; then
        echo "lock: no heartbeat for ${age}s, but the holder is ALIVE - the machine" >&2
        echo "      probably slept. Not taking over. $(lock_holder_line)" >&2
        quiet_alive=1
      fi
      age=0
    fi

    if [ "$age" -gt "$LOCK_STALE" ]; then
      echo "lock: the holder stopped breathing ${age}s ago - taking over" >&2
      echo "      it was: $(lock_holder_line)" >&2
      rm -rf "$LOCK_DIR"
      continue
    fi

    if [ "$announced" = 0 ]; then
      echo "lock: waiting - $(lock_holder_line)"
      echo "      (this machine runs one build or one suite run at a time;"
      echo "       'bash scripts/api.sh lock-status' to look, and nothing"
      echo "       here needs killing - it clears itself)"
      announced=1
    fi

    if [ "$waited" -ge "$LOCK_WAIT_MAX" ]; then
      echo "lock: still held after ${waited}s - giving up rather than hanging" >&2
      echo "      $(lock_holder_line)" >&2
      return 1
    fi
    sleep 5
    waited=$((waited + 5))
  done
}

# cmd_lock_status distinguishes a HELD lock from a DEAD one, because the
# two call for opposite things and the word "held" alone reads as the
# first.
#
# A run killed hard leaves the directory behind - measured, and the trap
# is not reliable enough to prevent it. The stale rule clears it within
# LOCK_STALE seconds the moment anybody actually wants the lock, so it
# costs nothing. But somebody running lock-status meanwhile saw
# "held: a session (verify, pid 22140) since 05:25:13" on a lock whose
# holder had been gone ninety-five minutes, and the honest response to
# that line is to wait for a process that no longer exists.
cmd_lock_status() {
  if [ ! -d "$LOCK_DIR" ]; then echo 'free'; return 0; fi

  local beat age
  beat="$(date -r "$LOCK_DIR/beat" +%s 2>/dev/null || echo 0)"
  age=$(( $(date +%s) - beat ))

  if [ "$age" -gt "$LOCK_STALE" ] && ! lock_holder_alive; then
    echo "DEAD: $(lock_holder_line)"
    echo '      nothing is running behind this. The next build or run takes'
    echo "      it over on its own; 'api.sh unlock' clears it now."
  else
    echo "held: $(lock_holder_line)"
  fi
  echo "at:   $LOCK_DIR"
}

# cmd_unlock is the escape hatch, and it REFUSES a lock that is alive.
#
# It exists because the alternative is somebody deleting the directory by
# hand at three in the morning, which they will do on a live lock and
# hand the machine to two runs at once. So there is a supported way, and
# it is the same rule the waiter uses: gone means no breath for
# LOCK_STALE seconds, not "I would like it now".
#
# Waiting also works and needs no command - the next acquire takes over
# on its own. This is for somebody who wants it back this second.
cmd_unlock() {
  if [ ! -d "$LOCK_DIR" ]; then echo 'free - nothing to do'; return 0; fi

  local beat age
  beat="$(date -r "$LOCK_DIR/beat" +%s 2>/dev/null || echo 0)"
  age=$(( $(date +%s) - beat ))

  if [ "$age" -le "$LOCK_STALE" ] || lock_holder_alive; then
    echo "refusing: the holder is alive - $(lock_holder_line)" >&2
    echo "          it breathed ${age}s ago, and the threshold is ${LOCK_STALE}s." >&2
    echo "          Breaking a live lock puts two runs on one container and" >&2
    echo "          produces a number that describes neither. Wait, or ask" >&2
    echo "          whoever holds it to stop." >&2
    return 1
  fi

  echo "breaking a dead lock: $(lock_holder_line)"
  rm -rf "$LOCK_DIR"
  echo 'free'
}
