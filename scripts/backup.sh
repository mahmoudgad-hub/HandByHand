#!/usr/bin/env bash
# =====================================================================
# Hand By Hand (new) - take a backup, and PROVE it is one
#
#   bash scripts/backup.sh          take a full dump and verify it
#   bash scripts/backup.sh health   is there a recent verified backup?
#   bash scripts/backup.sh list     the last ten runs
#
# The verification is the point. A dump that has never been restored is
# a file, and the day you discover which it was is the worst possible
# day. So every dump this script takes is restored into a scratch
# database, its tables and rows are counted, the scratch database is
# dropped, and the result - verified or not - is written to
# hbh.backup_runs. hbh.v_backup_health then answers "are we backed up"
# with a row instead of with somebody's memory.
#
# WHERE THE DUMP LANDS, AND WHY NOT NEXT TO THE CODE
#
# It used to land in backups/ inside the project - which sits under
# OneDrive on this machine. So every dump, containing the complete
# clinical record of every child in the centre, was being uploaded to a
# consumer cloud account automatically. Nobody decided that; it followed
# from where the project folder happens to live.
#
# So the default is now OUTSIDE any sync folder, and this script REFUSES
# to write into one. Override with BACKUP_DIR only to a path you have
# actually thought about.
#
# Copying it off the machine is still a separate concern and still not
# automated: a backup on the same disk as the database is not a backup,
# and pretending otherwise in a script would be worse than leaving it
# obvious.
# =====================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT/deploy/compose/docker-compose.yml"
OUT_DIR="${BACKUP_DIR:-$HOME/hbh-backups}"

# A dump is the whole clinical record in one file. A sync client turns
# "on this machine" into "on somebody's servers" without asking, so the
# refusal is hard rather than a warning - a warning scrolls past.
case "$OUT_DIR" in
  *OneDrive*|*Dropbox*|*"Google Drive"*|*iCloud*|*Box*|*pCloud*|*MEGA*)
    echo "  *** REFUSING: $OUT_DIR is inside a cloud sync folder." >&2
    echo "      A dump holds every child's clinical record. Syncing it to a" >&2
    echo "      consumer cloud account is a decision, not a default." >&2
    echo "      Set BACKUP_DIR to somewhere outside the sync folder." >&2
    exit 2 ;;
esac

if [ -f "$ROOT/.env" ]; then set -a; . "$ROOT/.env"; set +a; fi
: "${DB_OWNER_PASSWORD:=hbh_dev_only_change_me}"
export DB_OWNER_PASSWORD

dc()    { docker compose -f "$COMPOSE_FILE" "$@"; }
psqlq() { dc exec -T db psql -v ON_ERROR_STOP=1 -U hbh_owner -d hbh -tAc "$1"; }

cmd_health() {
  dc exec -T db psql -U hbh_owner -d hbh -c "SELECT * FROM hbh.v_backup_health;"
}

cmd_list() {
  dc exec -T db psql -U hbh_owner -d hbh -c \
    "SELECT backup_id, finished_at, kind, file_name, size_bytes,
            verified_flg, verified_tables, verified_rows, ok_flg, detail
     FROM hbh.backup_runs ORDER BY backup_id DESC LIMIT 10;"
}

cmd_backup() {
  mkdir -p "$OUT_DIR"
  local stamp file scratch size sha tables rows ok detail
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  file="hbh-$stamp.dump"
  scratch="hbh_verify_$$"
  ok=false
  detail=""

  echo "  dumping   $file"
  # Custom format: compressed, and pg_restore can read it selectively.
  dc exec -T db pg_dump -U hbh_owner -d hbh -Fc > "$OUT_DIR/$file"

  size=$(wc -c < "$OUT_DIR/$file" | tr -d ' ')
  sha=$(sha256sum "$OUT_DIR/$file" | cut -d' ' -f1)
  echo "  size      $size bytes"
  echo "  sha256    ${sha:0:16}..."

  if [ "$size" -lt 1024 ]; then
    detail="dump is only $size bytes - refusing to call that a backup"
    echo "  *** $detail" >&2
  else
    # ---------------------------------------------------------------
    # The verification. Restore into a throwaway database and count
    # what came back.
    # ---------------------------------------------------------------
    echo "  verifying by restoring into $scratch"
    dc exec -T db createdb -U hbh_owner "$scratch"

    if dc exec -T db pg_restore -U hbh_owner -d "$scratch" --no-owner --no-privileges \
         < "$OUT_DIR/$file" >/dev/null 2>&1; then
      tables=$(dc exec -T db psql -tAc \
        "SELECT count(*) FROM information_schema.tables
          WHERE table_schema='hbh' AND table_type='BASE TABLE'" -U hbh_owner -d "$scratch" | tr -d '\r')
      rows=$(dc exec -T db psql -tAc \
        "SELECT coalesce(sum(n_live_tup),0) FROM pg_stat_user_tables
          WHERE schemaname='hbh'" -U hbh_owner -d "$scratch" | tr -d '\r')

      # A restore that produces an empty schema is a restore that
      # worked on nothing.
      if [ "${tables:-0}" -ge 20 ]; then
        ok=true
        echo "  restored  $tables tables"
      else
        detail="restore produced only ${tables:-0} tables"
        echo "  *** $detail" >&2
      fi
    else
      detail="pg_restore failed"
      echo "  *** $detail" >&2
    fi

    dc exec -T db dropdb -U hbh_owner --if-exists "$scratch" || true
  fi

  # Ordinary single quotes, not dollar quoting: in a double-quoted shell
  # string $$ is the shell's own process id, so $$$file$$ expanded to
  # "237hbh-....dump" and Postgres reported trailing junk after a
  # numeric literal. The values here are a filename, a hex digest and a
  # message this script wrote, so a quote-doubling is all they need.
  local q_detail="NULL"
  [ -n "$detail" ] && q_detail="'$(printf '%s' "$detail" | sed "s/'/''/g")'"

  psqlq "SELECT hbh.record_backup('FULL', '$file', $size, '$sha',
           $( [ "$ok" = true ] && echo true || echo false ),
           ${tables:-NULL}, ${rows:-NULL},
           $( [ "$ok" = true ] && echo true || echo false ),
           $q_detail)" >/dev/null

  if [ "$ok" = true ]; then
    echo "  VERIFIED  $OUT_DIR/$file"
    echo
    echo "  Outside any sync folder - but still on the same disk as the"
    echo "  database. Copying it OFF the machine is not automated."
    return 0
  fi
  echo "  *** BACKUP NOT VERIFIED - see hbh.backup_runs" >&2
  return 1
}

case "${1:-backup}" in
  backup) cmd_backup ;;
  health) cmd_health ;;
  list)   cmd_list ;;
  *)      sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
