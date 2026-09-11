#!/usr/bin/env bash
# =====================================================================
# Hand By Hand (new) - API driver
#
# Nothing is installed on the host. The Go toolchain lives in a
# container and every command below reaches it through docker.
#
#   bash scripts/api.sh build    build the image (runs vet + unit tests)
#   bash scripts/api.sh up       build if needed, start, wait for /healthz
#   bash scripts/api.sh test     unit tests only, no image, no database
#   bash scripts/api.sh fmt      gofmt the tree in place, then lint
#   bash scripts/api.sh lint     refuse status codes written as numbers
#   bash scripts/api.sh verify   every API acceptance suite  (verify 2 = one)
#   bash scripts/api.sh logs     tail the service log
#   bash scripts/api.sh sh       a shell in the Go toolchain container
#   bash scripts/api.sh down     stop the API (the database keeps running)
# =====================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT/deploy/compose/docker-compose.yml"

if [ -f "$ROOT/.env" ]; then
  set -a; . "$ROOT/.env"; set +a
fi

: "${DB_OWNER_PASSWORD:=hbh_dev_only_change_me}"
: "${DB_APP_PASSWORD:=hbh_app_dev_only_change_me}"
: "${DB_PORT:=5434}"
: "${API_PORT:=8090}"
: "${GO_IMAGE:=golang:1.24-alpine}"
export DB_OWNER_PASSWORD DB_APP_PASSWORD DB_PORT API_PORT

dc() { docker compose -f "$COMPOSE_FILE" "$@"; }

# Docker on this host is reached from Git Bash, which rewrites anything
# that looks like a Unix path inside a command line. MSYS_NO_PATHCONV
# turns that off; without it, -w /src arrives as a Windows path and the
# daemon refuses it.
go_in_container() {
  local host_api
  host_api="$(cd "$ROOT/api" && pwd -W 2>/dev/null || echo "$ROOT/api")"
  MSYS_NO_PATHCONV=1 docker run --rm ${GO_TTY:-} \
    -v "$host_api:/src" -w /src \
    -e GOFLAGS=-mod=mod \
    "$GO_IMAGE" sh -c "$1"
}

cmd_test() { go_in_container 'go vet ./... && go test ./...'; }
cmd_fmt()  { go_in_container 'gofmt -w . && gofmt -l .' && cmd_lint; }

# cmd_lint catches what gofmt cannot see.
#
# A STATUS CODE WRITTEN AS A NUMBER compiles whatever it is. gofmt will
# happily lay out writeError(w, r, 304, CodeForbidden) and go vet has no
# opinion about it, so a refusal answered as "not modified" ships and the
# only thing that notices is a browser doing something strange much later.
#
# Two files reached this repository with 403, 400 and 200 spelled as
# digits while their own neighbouring lines used the constants. They were
# reformatted and the numbers survived the reformatting untouched - which
# is the whole reason this check is separate from gofmt rather than
# trusted to it.
#
# The pattern deliberately matches only the two writers this service
# answers through. Anything else is somebody's loop counter.
cmd_lint() {
  local hits
  hits="$(grep -rnE 'write(Error|ErrorFields|JSON)\(w, r?e?q?,? *[0-9]{3},' \
            "$ROOT/api/internal" 2>/dev/null | grep -v '^\s*//' | grep -v '// ' || true)"
  if [ -n "$hits" ]; then
    echo 'status codes written as numbers - use the net/http constants:' >&2
    echo "$hits" >&2
    return 1
  fi
  echo 'lint: no raw status codes'
  cmd_doc_drift && cmd_search_drift && cmd_like_escape
}

# cmd_like_escape refuses a LIKE pattern that obeys what somebody typed.
#
# WHAT IT COST. Three search paths built their patterns the same way -
# `col ILIKE '%' || $3 || '%'` - and two of them named no escape
# character. The term is a bound parameter, so this was never injection;
# it was the quieter defect underneath. A receptionist who typed a single
# '%' was handed EVERY child in the centre, and '_' stood for any
# character rather than itself - which bites hardest on hbh.users, where
# every username in this schema HAS an underscore, so a search that
# looked right returned the wrong colleague.
#
# crud.go had solved it the day it was written: likeEscape() doubles the
# backslash, then escapes '%' and '_', and every pattern it builds ends
# ESCAPE '\'. portal.go and identity.go were written later and never got
# it. NOTHING CONNECTED THE THREE - which is what this check now is.
#
# WHAT IT PROVES, EXACTLY, is two halves:
#
#   1. no line puts a bound parameter inside a LIKE or ILIKE without
#      naming an escape character on that same line;
#   2. a file that builds such a pattern also calls likeEscape, because
#      ESCAPE '\' over a term nobody escaped is decoration - it names a
#      character that is never there.
#
# The second half is a FILE-level heuristic and says so: it cannot tell
# which bind site was escaped, only that the file knows the function
# exists. The bind site is still read by a person.
#
# A pattern wrapped across two lines is REPORTED, not skipped. A false
# positive there is fixed by joining the line; the alternative is a check
# that quietly stops seeing things, which is the defect it exists to
# prevent. Same reason the count is printed: if this ever says it read 0
# patterns, that is the bug, not a pass.
cmd_like_escape() {
  local candidates seen offenders unescaped files missing f

  # grep -rn prints file:line:content, so the comment filter anchors after
  # the line number - a `//` or `--` anywhere later is inside the SQL.
  candidates="$(grep -rnE '\bI?LIKE\b' "$ROOT/api/internal" --include='*.go' 2>/dev/null \
                | grep -E '\$[0-9]' \
                | grep -vE ':[0-9]+:[[:space:]]*(//|--)' || true)"

  seen="$(printf '%s' "$candidates" | grep -c . || true)"
  if [ "${seen:-0}" = 0 ]; then
    echo 'lint: read 0 LIKE patterns carrying a bound parameter -' >&2
    echo '      this check proved nothing. Either every search moved out' >&2
    echo '      of api/internal, or the pattern in cmd_like_escape is' >&2
    echo '      stale. Fix it rather than deleting it.' >&2
    return 1
  fi

  unescaped="$(printf '%s\n' "$candidates" | grep -v 'ESCAPE' || true)"
  if [ -n "$unescaped" ]; then
    echo 'a LIKE pattern over a typed term with no ESCAPE clause -' >&2
    echo "a '%' typed into that box matches every row the policy allows:" >&2
    printf '%s\n' "$unescaped" >&2
    return 1
  fi

  # The other half: the file that builds the pattern must know likeEscape.
  #
  # The name is cut by stripping the ":line:content" TAIL, never with
  # `cut -d: -f1`. A path here can begin "C:/Users/..." when ROOT is a
  # Windows path, and cutting on the first colon hands the whole check
  # the filename "C" - which then reports every file as missing
  # likeEscape, for a reason that names neither the file nor the drive.
  files="$(printf '%s\n' "$candidates" | sed -E 's/:[0-9]+:.*$//' | sort -u)"
  missing=''
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if ! grep -q 'likeEscape' "$f"; then missing="$missing$f"$'\n'; fi
  done <<< "$files"

  if [ -n "$missing" ]; then
    echo 'a LIKE pattern names ESCAPE in a file that never calls likeEscape -' >&2
    echo 'the escape character is declared and never written:' >&2
    printf '%s' "$missing" >&2
    return 1
  fi

  echo "lint: all $seen LIKE patterns over a typed term escape it"
}

# cmd_search_drift refuses a search box the service will refuse.
#
# WHAT IT COST. hbh.site_texts holds 112 rows and its screen drew a search
# box, because SITE_TEXTS_SPEC says `searchable: true`. The resource in
# crud.go had no `search` list, so the service answered every `?q=` with
#
#     400 VALIDATION - q (this resource has no searchable fields)
#
# and the screen showed its generic "تعذّر تحميل البيانات". Not "no
# results" - a load failure, on the one screen whose 112 rows are unusable
# without a search. Both sides were internally consistent and neither was
# wrong on its own; only the PAIR was. The owner read it as the database
# not feeding the console at all.
#
# It is the same shape as cmd_doc_drift above, and the same shape as the
# duplicate-migration check in db.sh: two files that must agree, nothing
# that makes them, and a failure that names neither.
#
# BOTH DIRECTIONS ARE REPORTED, and the second is not cosmetic. A resource
# with search columns and no `searchable: true` is a search that works and
# has no way in - the console draws no box, so the capability is written,
# tested, shipped and unreachable.
#
# It greps rather than parses, so the shapes it expects are narrow on
# purpose: an entry it cannot read is an entry it leaves out, and a check
# that silently sees nothing is the defect it exists to prevent. If this
# ever prints "0 of 0 agree", that is the bug, not a pass.
cmd_search_drift() {
  local specs="$ROOT/web/ops/src/app/core/resource/resource-spec.ts"
  local crud="$ROOT/api/internal/store/crud.go" tmp go_n ng_n only_ng only_go

  [ -f "$specs" ] || { echo "lint: no console specs at $specs - skipped"; return 0; }
  tmp="$(mktemp -d)"

  # A Go resource is searchable when its entry carries a `search` list.
  # The name is tracked from `Name:` and emitted at the entry's closing
  # brace, so a `search:` inside one entry can never be credited to
  # another - and the word "search" in the long comment above the field
  # is not matched, because the pattern demands the declaration.
  awk '
    /^\t\{/ { name=""; has=0; next }
    /Name: "/ { if (match($0,/Name: "[a-z0-9-]+"/)) name=substr($0,RSTART+7,RLENGTH-8) }
    /^[ \t]*search:[ \t]*\[\]string\{/ { has=1 }
    /^\t\},/ { if (name != "" && has) print name; name=""; has=0 }
  ' "$crud" | sort -u > "$tmp/go"

  # A console resource is searchable when its spec says so. `resource:`
  # is carried forward because it is written above `searchable:` in every
  # spec; day-spec.ts is scanned too, though its DaySpec type has no such
  # field today - the day it gains one, this notices.
  awk '
    /resource: '"'"'[a-z0-9-]+'"'"'/ {
      if (match($0,/resource: '"'"'[a-z0-9-]+'"'"'/))
        name=substr($0,RSTART+11,RLENGTH-12)
    }
    /^[ \t]*searchable:[ \t]*true/ { if (name != "") print name }
  ' "$specs" "$ROOT/web/ops/src/app/core/ops/day-spec.ts" 2>/dev/null \
    | sort -u > "$tmp/ng"

  go_n="$(wc -l < "$tmp/go" | tr -d ' ')"
  ng_n="$(wc -l < "$tmp/ng" | tr -d ' ')"
  if [ "$go_n" = 0 ] || [ "$ng_n" = 0 ]; then
    echo "lint: read $go_n searchable resources and $ng_n searchable specs -" >&2
    echo "      one side came back empty, so this check proved nothing." >&2
    echo "      The file shapes changed; fix the patterns in cmd_search_drift." >&2
    rm -rf "$tmp"
    return 1
  fi

  only_ng="$(comm -13 "$tmp/go" "$tmp/ng")"
  only_go="$(comm -23 "$tmp/go" "$tmp/ng")"

  if [ -n "$only_ng" ] || [ -n "$only_go" ]; then
    echo 'the console and the service disagree about search:' >&2
    if [ -n "$only_ng" ]; then
      echo '  a search box the service will answer 400 to -' >&2
      echo '  add a `search` list in crud.go, or drop `searchable`:' >&2
      printf '    %s\n' $only_ng >&2
    fi
    if [ -n "$only_go" ]; then
      echo '  searchable in the service with no way to reach it -' >&2
      echo '  add `searchable: true` to the spec, or drop `search`:' >&2
      printf '    %s\n' $only_go >&2
    fi
    rm -rf "$tmp"
    return 1
  fi

  rm -rf "$tmp"
  echo "lint: console and service agree on all $go_n searchable resources"
}

# cmd_doc_drift refuses a route the contract does not mention.
#
# docs/02-api-contract.md is what the console and the portal are written
# against, and it fell 33 routes behind over one week without anything
# saying so - a document goes stale silently, which is the whole
# difference between it and code. Two batches of that gap were mine.
#
# WHAT THIS PROVES, EXACTLY: that every path registered in server.go
# appears somewhere in the contract, with parameter NAMES ignored so
# {id} and {child_id} match, and with a leading "…" in the document
# treated as "any prefix" because the tables are written that way. It
# does NOT prove the description is correct, or current, or that the
# verbs match. A route can be listed and wrong.
#
# That narrowness is deliberate and worth stating: an earlier check of
# mine compared paths one way and I reported the answer as though it had
# compared them both ways. A check proves what it asks and not what its
# name suggests.
cmd_doc_drift() {
  local doc="$ROOT/docs/02-api-contract.md" tmp missing
  tmp="$(mktemp -d)"

  grep -oE '"/api/v1/[^"]*"' "$ROOT/api/internal/http/server.go" \
    | tr -d '"' | sed 's/{[a-z_]*}/{}/g' | sort -u > "$tmp/routes"
  grep -oE '(…)?/api/v1/[a-z0-9/{}_-]+|…/[a-z0-9/{}_-]+' "$doc" \
    | sed 's/{[a-z_]*}/{}/g' | sed 's:/$::' | sort -u > "$tmp/doc"

  # The suffixes the document writes as "…/activities/{}/log", with the
  # ellipsis stripped. Matched with shell globbing, never with grep -E:
  # a path containing {} is a regex interval to ERE, and the error it
  # gives - "Invalid content of \{\}" - names neither the pattern nor
  # the file.
  sed -n 's/^…//p' "$tmp/doc" | grep '^/' | sort -u > "$tmp/suffix" || true

  missing=""
  while read -r route; do
    grep -qxF "$route" "$tmp/doc" && continue
    local covered=0 s
    while read -r s; do
      [ -n "$s" ] || continue
      case "$route" in *"$s") covered=1; break ;; esac
    done < "$tmp/suffix"
    [ "$covered" = 1 ] && continue
    missing="$missing  $route"$'\n'
  done < "$tmp/routes"

  if [ -n "$missing" ]; then
    echo 'routes the API contract does not mention:' >&2
    printf '%s' "$missing" >&2
    echo "  -> docs/02-api-contract.md" >&2
    rm -rf "$tmp"
    return 1
  fi
  local n
  n="$(wc -l < "$tmp/routes" | tr -d ' ')"
  rm -rf "$tmp"
  echo "lint: all $n routes appear in the contract"
}

cmd_build() { dc build api; }

wait_healthy() {
  printf 'waiting for hbhd'
  local i
  for ((i = 0; i < 40; i++)); do
    if curl -fsS "http://127.0.0.1:$API_PORT/healthz" >/dev/null 2>&1; then
      echo ' - ready'; return 0
    fi
    printf '.'; sleep 1
  done
  echo
  echo "hbhd did not answer on port $API_PORT within 40s" >&2
  dc logs --tail 60 api >&2
  return 1
}

cmd_up() {
  dc up -d --build api
  wait_healthy
}

# verify [n]   one batch, or every batch in order when n is omitted.
cmd_verify() {
  cmd_up
  local want="${1:-}" status=0 batch

  # A glob into an array and an index. Never $(ls): this project lives
  # under a path containing a space - "سطح المكتب" - and command
  # substitution word-splits it into two nonexistent paths.
  local suites=("$ROOT"/tests/api/a*_verify.sh)
  local i f
  for ((i = 0; i < ${#suites[@]}; i++)); do
    f="${suites[i]}"
    [ -e "$f" ] || continue
    batch="$(basename "$f" | sed 's/^a\([0-9]*\)_verify\.sh$/\1/')"
    if [ -n "$want" ] && [ "$want" != "$batch" ]; then continue; fi

    # Restart before EVERY suite, not once per run. The login rate
    # limiter lives in process memory, and one suite deliberately empties
    # its bucket - so without this the next suite cannot log in, and
    # fails for a reason that has nothing to do with what it tests.
    dc restart api >/dev/null
    wait_healthy || return 1

    # An explicit assignment, never "${rc:-1}". A `local out rc=0`
    # swallows the exit code of the command on the same line, which
    # reads a failure as a pass - a bug this project already paid for.
    API_BASE="http://127.0.0.1:$API_PORT" bash "$f" || status=1
  done
  return "$status"
}

case "${1:-}" in
  build)  cmd_build ;;
  up)     cmd_up ;;
  test)   cmd_test ;;
  fmt)    cmd_fmt ;;
  lint)   cmd_lint ;;
  verify) cmd_verify "${2:-}" ;;
  logs)   dc logs --tail "${2:-80}" -f api ;;
  sh)     GO_TTY='-it' go_in_container 'sh' ;;
  down)   dc stop api && dc rm -f api ;;
  *)
    sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 1 ;;
esac
