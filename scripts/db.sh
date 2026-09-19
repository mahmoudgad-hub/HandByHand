#!/usr/bin/env bash
# =====================================================================
# Hand By Hand (new) - database driver
#
# Nothing is installed on the host. Postgres runs in a container and
# every command below reaches it through docker compose.
#
#   bash scripts/db.sh up        start Postgres and wait until healthy
#   bash scripts/db.sh migrate   apply pending migrations, then the seed
#   bash scripts/db.sh verify    run the acceptance suite
#   bash scripts/db.sh reset     drop everything and rebuild from zero
#   bash scripts/db.sh dev-user  development staff accounts (needs DEV_STAFF_PASSWORD)
#   bash scripts/db.sh dev-family  a family that can sign in to the portal, with data
#   bash scripts/db.sh psql      interactive shell as the owner
#   bash scripts/db.sh app       interactive shell as the API role
#   bash scripts/db.sh maintenance  run the periodic work once, now
#   bash scripts/db.sh health       is the periodic work actually running?
#   bash scripts/db.sh sms-health   is the outbox draining, and is it switched on?
#   bash scripts/db.sh sms-pause    stop the outbox during a provider fault
#   bash scripts/db.sh sms-resume   start it again
#   bash scripts/db.sh down      stop the container (data is kept)
#   bash scripts/db.sh nuke      stop and DELETE the data volume
# =====================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT/deploy/compose/docker-compose.yml"

# The same lock api.sh build/up/verify take. See cmd_migrate below.
. "$ROOT/scripts/lock.sh"

# Local overrides, if any. Never committed - see .gitignore.
if [ -f "$ROOT/.env" ]; then
  set -a; . "$ROOT/.env"; set +a
fi

: "${DB_OWNER_PASSWORD:=hbh_dev_only_change_me}"
: "${DB_APP_PASSWORD:=hbh_app_dev_only_change_me}"
: "${DB_PORT:=5434}"
export DB_OWNER_PASSWORD DB_APP_PASSWORD DB_PORT

# ---------------------------------------------------------------------
# How this script reaches the database.
#
#   container   (default) Postgres in compose - developer machines, CI.
#   native      a cluster running under $HOME, on a host where this
#               account has no access to docker at all.
#
# Only the transport differs. The ordering, the duplicate-number guard,
# the migration bookkeeping and every line of SQL are the same code in
# both, because a migration that behaves one way here and another way
# there is worse than having no second mode.
#
# The mode is never inferred. A host carrying both would otherwise pick
# one silently and migrate the wrong database without saying so.
# ---------------------------------------------------------------------
DB_MODE="${HBH_DB_MODE:-container}"

case "$DB_MODE" in
  container)
    dc() { docker compose -f "$COMPOSE_FILE" "$@"; }
    # -T because these run without a TTY; ON_ERROR_STOP so a broken
    # migration stops instead of limping on and reporting success.
    psqlf()     { dc exec -T db psql -v ON_ERROR_STOP=1 -U hbh_owner -d hbh "$@"; }
    # A suite runs WITHOUT ON_ERROR_STOP on purpose - see run_suite.
    psqlsuite() { dc exec -T db psql -U hbh_owner -d hbh "$@"; }

    wait_healthy() {
      printf 'waiting for postgres'
      for _ in $(seq 1 40); do
        if dc exec -T db pg_isready -U hbh_owner -d hbh >/dev/null 2>&1; then
          echo ' - ready'; return 0
        fi
        printf '.'; sleep 1
      done
      echo; echo 'postgres did not become ready in 40s' >&2
      dc logs --tail 40 db >&2
      return 1
    }
    db_up() {
      # Only the database. The compose file also defines the api service,
      # and a script called db.sh has no business building or restarting
      # it - least of all while somebody is working on it.
      dc up -d db
      wait_healthy
    }
    db_down()   { dc down; }
    db_nuke()   { dc down -v; }
    db_shell()  { dc exec db psql -U hbh_owner -d hbh; }
    db_app()    { dc exec -e PGPASSWORD="$DB_APP_PASSWORD" db psql -U hbh_app -d hbh -h 127.0.0.1; }
    db_logs()   { dc logs --tail "${1:-60}" db; }
    ;;

  native)
    PGBIN="${HBH_PG_BIN:-$HOME/pgsql/usr/lib/postgresql/17/bin}"
    PGDATA_DIR="${HBH_PGDATA:-$HOME/pgdata}"
    PGLOGDIR="${HBH_PGLOG:-$HOME/pglog}"
    [ -x "$PGBIN/psql" ] || { echo "db.sh: no psql under $PGBIN" >&2; exit 1; }
    # The bundle carries every library it needs except glibc, which has
    # to come from the host and does.
    export LD_LIBRARY_PATH="${HBH_PG_DEPS:-$HOME/pgsql/deps}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

    dc() { echo "db.sh: '${1:-?}' is a container operation and native mode has no compose project" >&2; return 2; }

    # PGPASSWORD is set per invocation rather than exported once: this
    # script also starts an interactive shell as a different role, and a
    # leftover export would silently offer the owner's password there.
    psqlf()     { PGPASSWORD="$DB_OWNER_PASSWORD" "$PGBIN/psql" -h 127.0.0.1 -p "$DB_PORT" -v ON_ERROR_STOP=1 -U hbh_owner -d hbh "$@"; }
    psqlsuite() { PGPASSWORD="$DB_OWNER_PASSWORD" "$PGBIN/psql" -h 127.0.0.1 -p "$DB_PORT" -U hbh_owner -d hbh "$@"; }

    wait_healthy() {
      printf 'waiting for postgres'
      for _ in $(seq 1 40); do
        if "$PGBIN/pg_isready" -h 127.0.0.1 -p "$DB_PORT" -U hbh_owner -d hbh >/dev/null 2>&1; then
          echo ' - ready'; return 0
        fi
        printf '.'; sleep 1
      done
      echo; echo 'postgres did not become ready in 40s' >&2
      tail -n 40 "$PGLOGDIR"/postgresql-*.log >&2 2>/dev/null
      return 1
    }
    db_up() {
      if ! "$PGBIN/pg_isready" -h 127.0.0.1 -p "$DB_PORT" -q 2>/dev/null; then
        mkdir -p "$PGLOGDIR"
        # The postmaster's environment is inherited by every backend, and
        # dblink - which is how an audit record survives the rollback of
        # the transaction it describes - is libpq running INSIDE one of
        # those backends. Its connection string carries only dbname and
        # user, so host and port come from these variables. Without them
        # libpq looks for a socket in the compiled-in /var/run/postgresql
        # on port 5432; this cluster is a home directory on 5434, the
        # connection fails, and audit_attempt turns that into a WARNING
        # by design. The request still succeeds, the audit row is simply
        # never written, and only the suites notice.
        PGHOST="${HBH_PGRUN:-$HOME/pgrun}" PGPORT="$DB_PORT" \
        "$PGBIN/pg_ctl" -D "$PGDATA_DIR" -l "$PGLOGDIR/startup.log" -w start || {
          echo 'postgres did not start' >&2
          tail -n 20 "$PGLOGDIR"/postgresql-*.log >&2 2>/dev/null
          return 1
        }
      fi
      wait_healthy
    }
    db_down()   { "$PGBIN/pg_ctl" -D "$PGDATA_DIR" -m fast -w stop; }
    # No native equivalent, and refusing is the point: 'nuke' deletes a
    # docker volume, while here it would mean rm -rf on a directory that
    # is the database itself.
    db_nuke()   { echo "db.sh: nuke is not available in native mode - remove $PGDATA_DIR deliberately if that is what you mean" >&2; return 2; }
    db_shell()  { PGPASSWORD="$DB_OWNER_PASSWORD" "$PGBIN/psql" -h 127.0.0.1 -p "$DB_PORT" -U hbh_owner -d hbh; }
    db_app()    { PGPASSWORD="$DB_APP_PASSWORD" "$PGBIN/psql" -h 127.0.0.1 -p "$DB_PORT" -U hbh_app -d hbh; }
    db_logs()   { tail -n "${1:-60}" "$PGLOGDIR"/postgresql-*.log; }
    ;;

  *)
    echo "db.sh: HBH_DB_MODE must be 'container' or 'native', got '$DB_MODE'" >&2
    exit 1 ;;
esac

cmd_up() { db_up; }

cmd_migrate() {
  wait_healthy

  # Two files claiming the same version number is how a migration gets
  # silently lost: the first one applies, records the version, and the
  # second is then "already applied" and skipped without a word. It has
  # happened once here already - two people numbered a migration 0003,
  # and the API's boot probe never reached the database.
  #
  # A skip that hides work is worse than a hard stop, so this is a hard
  # stop, before anything runs.
  local dupes
  dupes="$(for f in "$ROOT"/db/migrations/*.up.sql; do
             [ -e "$f" ] && basename "$f" | cut -d_ -f1
           done | sort | uniq -d)"
  if [ -n "$dupes" ]; then
    echo "duplicate migration version(s): $(echo "$dupes" | tr '\n' ' ')" >&2
    for v in $dupes; do
      echo "  claimed by:" >&2
      ls -1 "$ROOT"/db/migrations/"$v"_*.up.sql | sed 's|.*/|    |' >&2
    done
    echo "renumber one of them before running migrate" >&2
    return 1
  fi

  # The ledger is read ONCE, not once per file. It used to be a query
  # per migration - each its own docker exec, each about a second - so
  # `migrate` grew with the schema and by ninety migrations was taking
  # over two minutes to decide it had nothing to do. On a database three
  # sessions share, a command nobody wants to run is a command that
  # stops being run.
  local ledger
  ledger="$(psqlf -tAc "SELECT version FROM hbh.schema_migrations" 2>/dev/null | tr -d '\r')"

  # THE LOCK - taken only when there is something to apply.
  #
  # A migration is the commonest thing that moves the ground under an API
  # run, and until 2026-09-12 this command ignored the lock api.sh takes:
  # 0129 landed in the final suite of a full run and voided it. The pin
  # there detected it; nothing prevented it.
  #
  # ONLY WHEN PENDING, because the ordinary call has nothing to do. CI and
  # bring-up run migrate every time, and a no-op that waits forty minutes
  # behind somebody's suite run is a command people learn to skip - on a
  # shared database the most dangerous habit there is. Reading the ledger
  # moves nothing, so the check above stays outside.
  #
  # AND THE LEDGER IS READ AGAIN AFTER, because the wait is exactly when
  # another session applies the migration we were about to.
  #
  # The seeds below run inside the lock when it was taken and outside it
  # when it was not, as they always have: they are idempotent and do not
  # move the pinned ledger.
  local pending=0 pf pv
  for pf in "$ROOT"/db/migrations/*.up.sql; do
    [ -e "$pf" ] || continue
    pv="$(basename "$pf" | cut -d_ -f1)"
    if ! printf '%s\n' "$ledger" | grep -qx "$pv"; then pending=$((pending + 1)); fi
  done
  if [ "$pending" -gt 0 ]; then
    echo "  $pending migration(s) pending - taking the lock"
    lock_acquire migrate || return 1
    ledger="$(psqlf -tAc "SELECT version FROM hbh.schema_migrations" 2>/dev/null | tr -d '\r')"
  fi

  local applied=0
  for f in "$ROOT"/db/migrations/*.up.sql; do
    [ -e "$f" ] || continue
    local version; version="$(basename "$f" | cut -d_ -f1)"
    # Anchored on both sides: '008' must not match '0080'.
    if printf '%s\n' "$ledger" | grep -qx "$version"; then
      echo "  skip   $version (already applied)"
      continue
    fi
    # RE-READ, for this version only. The cached ledger above makes the
    # skip path fast; it also makes it STALE, and on a database three
    # sessions share, another session can apply a migration between that
    # read and this line. That is not theoretical - it happened on 0092
    # within minutes of the cache being introduced, and the run died on
    # "relation already exists" for a migration that was properly
    # applied and properly recorded.
    #
    # So: the cheap check for the ninety we skip, the true check for the
    # one or two we are about to run. One query where it matters, none
    # where it does not.
    if psqlf -tAc "SELECT 1 FROM hbh.schema_migrations WHERE version='$version'" 2>/dev/null | grep -q 1; then
      echo "  skip   $version (applied by another session just now)"
      continue
    fi

    echo "  apply  $version  $(basename "$f")"
    # --single-transaction: a migration lands whole or not at all.
    psqlf --single-transaction -v "app_password=$DB_APP_PASSWORD" -f - < "$f"
    applied=$((applied + 1))
  done

  for f in "$ROOT"/db/seed/*.sql; do
    [ -e "$f" ] || continue
    echo "  seed   $(basename "$f")"
    psqlf --single-transaction -f - < "$f"
  done

  echo "migrations applied: $applied"
}

# Runs one suite file and decides on its verdict line, not on psql's
# exit code. ON_ERROR_STOP is off inside a suite on purpose: every probe
# records its own failure so the verdict always prints, and the block
# after the verdict is what raises.
run_suite() {
  local file="$1" phase="$2" out
  out="$(psqlsuite -f - < "$file" 2>&1)" || true
  echo "$out"
  if echo "$out" | grep -q "PHASE $phase ACCEPTED"; then
    return 0
  fi
  echo
  if echo "$out" | grep -q 'NOT ACCEPTED'; then
    echo "*** phase $phase ran and was refused - see the failures above" >&2
  else
    echo "*** phase $phase did not reach its verdict at all - treat this as a failure" >&2
  fi
  return 1
}

# verify [n]   one phase, or every phase in order when n is omitted.
# The ground a verdict was measured on: migration COUNT and MAX, not
# max alone. Numbers are reserved before files are written, so a lower
# migration can land after a higher one and leave max untouched - which
# is exactly the case where "the schema did not move" would be a lie.
ledger_pin() {
  psqlf -tAc "SELECT count(*) || '|' || max(version) FROM hbh.schema_migrations" 2>/dev/null \
    | tr -d '\r[:space:]'
}

cmd_verify() {
  wait_healthy
  local want="${1:-}" failed=0 phase ran=0
  # A glob into an array - see the note in cmd_reset about $(ls).
  local suites=("$ROOT"/tests/db/p*_verify.sql)
  local f

  # DETECTION, NOT PREVENTION. Three sessions apply migrations to this
  # database. A run that straddles one of those produces a single total
  # describing two schemas and not a line saying which suite ran on
  # which - and a red result would then send somebody hunting in the
  # wrong one. api.sh verify has pinned its ground for this reason; this
  # did not, and a verdict from it could only be trusted after a manual
  # before-and-after check.
  #
  # Preventing the straddle is a lock, and a lock is the owner's call.
  # This only refuses to give a verdict it cannot vouch for.
  local pinned current
  pinned="$(ledger_pin)"
  echo "schema: ${pinned:-<unreadable>}"

  # An unreadable ground is not a ground. Without this, a ledger that
  # cannot be read at all - bad credentials, a wrong database - reads as
  # "" on every check, "" equals "", and the run reports the schema HELD
  # and exits 0. Found by measuring this guard, not by reading it: every
  # other case bit correctly and this one sailed through.
  if [ -z "$pinned" ]; then
    echo "*** RUN VOID - the migration ledger could not be read, so there is no ground to measure on" >&2
    return 2
  fi

  for f in "${suites[@]}"; do
    [ -e "$f" ] || continue
    phase="$(basename "$f" | sed 's/^p\([0-9a-z]*\)_verify\.sql$/\1/')"
    if [ -n "$want" ] && [ "$want" != "$phase" ]; then continue; fi

    current="$(ledger_pin)"
    if [ "$current" != "$pinned" ]; then
      echo "*** RUN VOID - the schema moved before phase $phase" >&2
      echo "    schema pinned: ${pinned} / now ${current:-<unreadable>}" >&2
      echo "    no verdict: the suites so far measured one schema and the rest would measure another" >&2
      return 2
    fi

    echo "=================== phase $phase ==================="
    ran=$((ran + 1))
    run_suite "$f" "$phase" || failed=1
  done

  # And once after the last suite, which a check-before-each alone misses.
  current="$(ledger_pin)"
  if [ "$current" != "$pinned" ]; then
    echo "*** RUN VOID - the schema moved during the final suite" >&2
    echo "    schema pinned: ${pinned} / now ${current:-<unreadable>}" >&2
    return 2
  fi

  # RAN NOTHING IS NOT A PASS. bring-up.sh called this with "p00" while the
  # phase derived from p00_verify.sql is "00" - so `want` matched no file,
  # the loop skipped every suite, `failed` stayed 0, and the schema-wide
  # conventions gate - the only guard over rules 3 and 4 - printed OK on
  # every deploy having run zero checks. It sat that way a week. Same
  # family as ng test returning 0 with no browser: the exit code alone does
  # not say anything ran.
  if [ "$ran" -eq 0 ]; then
    if [ -n "$want" ]; then
      echo "*** phase '$want' matched no suite - it ran nothing, which is not a pass" >&2
      printf '    available phases:' >&2
      for f in "${suites[@]}"; do
        [ -e "$f" ] && printf ' %s' \
          "$(basename "$f" | sed 's/^p\([0-9a-z]*\)_verify\.sql$/\1/')" >&2
      done
      echo >&2
    else
      echo "*** no p*_verify.sql suites under tests/db - nothing to run" >&2
    fi
    return 2
  fi

  echo "schema: ${pinned} (held for the whole run)"
  return "$failed"
}

# dev-user   create the development staff accounts.
#
# NOT part of migrate, and deliberately not in db/seed/: every file
# there runs on every install, so a staff account with a password in
# db/seed/ would be created on production too, with a password written
# in the repository.
#
# The password comes from the environment and has no default. Running
# this without one is an error rather than an account everybody can
# guess.
cmd_dev_user() {
  wait_healthy
  if [ -z "${DEV_STAFF_PASSWORD:-}" ]; then
    echo "set DEV_STAFF_PASSWORD first - there is deliberately no default:" >&2
    echo "  DEV_STAFF_PASSWORD='a long development password' bash scripts/db.sh dev-user" >&2
    return 1
  fi
  # The length rule is here, not in the SQL: psql does not substitute a
  # variable inside a dollar-quoted block, so a DO block cannot see it.
  if [ "${#DEV_STAFF_PASSWORD}" -lt 12 ]; then
    echo "DEV_STAFF_PASSWORD must be at least 12 characters - a short development password is the one that gets reused" >&2
    return 1
  fi
  psqlf --single-transaction -v "staff_password=$DEV_STAFF_PASSWORD" \n        -f - < "$ROOT/db/dev/staff_accounts.sql"
}

# dev-family creates a family that can actually sign in to the portal.
#
# There is no password to pass: families authenticate with a one-time
# code, and in development OTP_ECHO returns it in the response. So unlike
# dev-user this needs no secret - but it lives in db/dev/ for the same
# reason, because a demo family in db/seed/ would be created on every
# database this project is ever installed on.
#
# --single-transaction: the file books an appointment, runs a session and
# issues an invoice through the real functions. Half of that is worse
# than none - it leaves somebody debugging an empty screen against
# correct code.
cmd_dev_family() {
  wait_healthy
  psqlf --single-transaction -f - < "$ROOT/db/dev/demo_family.sql"
}

cmd_reset() {
  wait_healthy
  # Always locked, and for the whole of it: the downs are the part that
  # pulls the schema out from under a run, and they come BEFORE migrate.
  # The migrate call at the end is re-entrant on the same token. (reset
  # is still forbidden on a shared database - a lock does not make it
  # safe to drop somebody's data, it only stops it landing mid-run.)
  lock_acquire reset || return 1
  echo 'dropping schema and role'
  # An array and an index, not $(ls). This project lives under a path
  # containing a space - "سطح المكتب" - and command substitution
  # word-splits it into two nonexistent paths.
  local downs=("$ROOT"/db/migrations/*.down.sql)
  local i f
  for ((i = ${#downs[@]} - 1; i >= 0; i--)); do
    f="${downs[i]}"
    [ -e "$f" ] || continue
    echo "  down   $(basename "$f")"
    psqlf --single-transaction -f - < "$f"
  done
  cmd_migrate
}

case "${1:-}" in
  up)      cmd_up ;;
  migrate) cmd_migrate ;;
  verify)  cmd_verify "${2:-}" ;;
  reset)    cmd_reset ;;
  dev-user) cmd_dev_user ;;
  dev-family) cmd_dev_family ;;
  psql)    db_shell ;;
  app)     db_app ;;
  down)    db_down ;;
  nuke)    db_nuke ;;
  maintenance) psqlf -c 'SELECT hbh.run_maintenance();' ;;
  health)  psqlf -c 'SELECT * FROM hbh.v_maintenance_health;' ;;
  # THE OUTBOX. sending_paused is somebody's decision and is_stalled is
  # the worker being gone - different questions, which is why the view
  # keeps them apart. Migration 0115.
  sms-health) psqlf -c 'SELECT * FROM hbh.v_sms_health;' ;;
  # THE OFF SWITCH, so a fault at the gateway does not need a redeploy.
  #
  # NOTHING IS LOST WHILE IT IS OFF. Rows stay PENDING, no attempt is
  # counted against SMS_MAX_ATTEMPTS, next_attempt_at is untouched, and
  # they drain in order when it comes back.
  #
  # AND IT DOES NOT STOP ANYBODY SIGNING IN. A login code never enters
  # this queue - the handler sends it inside the request that asked for
  # it, and the outbox row is written afterwards as evidence.
  #
  # The state is printed afterwards rather than assumed: a switch you
  # cannot see is how a centre goes quiet for a week.
  sms-pause)
    psqlf -c "UPDATE hbh.sys_params SET param_value='false', updated_at=now(), updated_by=hbh.current_app_user() WHERE param_code='SMS_SENDING_ENABLED' AND center_id IS NULL;"
    psqlf -c 'SELECT center_id, sending_paused, pending_cnt, due_now_cnt FROM hbh.v_sms_health;' ;;
  sms-resume)
    psqlf -c "UPDATE hbh.sys_params SET param_value='true', updated_at=now(), updated_by=hbh.current_app_user() WHERE param_code='SMS_SENDING_ENABLED' AND center_id IS NULL;"
    psqlf -c 'SELECT center_id, sending_paused, pending_cnt, due_now_cnt FROM hbh.v_sms_health;' ;;
  logs)    db_logs "${2:-60}" ;;
  *)
    sed -n '2,23p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 1 ;;
esac
