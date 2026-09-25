#!/usr/bin/env bash
# W4 - the contact map's tiles are allowed by the policy that serves them.
#
#   bash tests/web/w4_map_tiles_csp.sh                 the source check
#   W4_ORIGIN=http://127.0.0.1:8094 bash ...w4...      and the live header
#
# WHAT WENT WRONG, and why a source check catches it where reading could
# not. site/contact-map.js draws the centre's location from OpenStreetMap
# image tiles. The static server that faces the internet answers with
# `img-src 'self' data:` - no tile host - so every tile is blocked, with
# any value in the console's map field. The page degrades honestly (it
# says so and offers the Google Maps button), and that is exactly why
# nobody noticed: the visible failure looks like a slow third party.
#
# Measured 2026-09-22 by serving site/ through deploy/server/web.native.mjs
# in static mode and scrolling with a real mouse: 8 tiles requested, 0
# loaded, 8 failed, and the console said eight times over -
#   Loading the image 'https://tile.openstreetmap.org/16/38497/27037.png'
#   violates the following Content Security Policy directive:
#   "img-src 'self' data:". The action has been blocked.
# The same tree behind site.native.mjs loaded all 8. Two programs serve
# this one directory and only one of them permits the map.
#
# THE ALLOWLIST IS DERIVED FROM THE CODE THAT REQUESTS IT, not typed here.
# The host is read out of contact-map.js, so the day somebody moves to a
# different tile provider this suite asks about the new host by itself. A
# hard-coded 'tile.openstreetmap.org' would have gone green over a policy
# that permits a host nothing requests any more - the decoration this
# project keeps paying for.
#
# WHAT THIS DOES NOT PROVE: that the map draws. Tiles arrive only after a
# real scroll in a real browser, and no shell check sees that. This asks
# the one question a file can answer - is the door open - and the browser
# measurement above is what proved it shut.
set -uo pipefail
cd "$(dirname "$0")/../.."

# Overridable so the guard can be PROVEN on a fixture tree. A guard seen
# only to pass has not been seen, and breaking a real policy file to watch
# it bite reaches into a tree another session may be serving from now.
ROOT="${W4_ROOT:-$PWD}"
SCOPE="${W4_SCOPE:-$ROOT/tests/web/map-csp-scope.tsv}"
TILES_JS="${W4_TILES_JS:-$ROOT/site/contact-map.js}"
ORIGIN="${W4_ORIGIN:-}"

pass=0; fail=0; ran=0
ok()   { printf '  ok    %s\n' "$1"; pass=$((pass+1)); ran=$((ran+1)); }
bad()  { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); ran=$((ran+1)); }
die()  { printf '\n  W4 ABORT: %s\n\n' "$1" >&2; exit 1; }

# --- what the page actually asks for --------------------------------------
[ -f "$TILES_JS" ] || die "$TILES_JS does not exist - the map script moved; point W4_TILES_JS at it rather than let an empty scan pass as a clean one"

# Hosts of every https URL this script loads images from. `sed` rather than
# `grep -o | cut -d/`: a path segment is not a host, and cutting at the
# first colon on a Windows path is how a lint once reported every file in
# the tree (the MSYS_NO_PATHCONV family in CLAUDE.md).
HOSTS="$(sed -nE "s#.*img\.src *= *'(https://[a-z0-9.-]+)/.*#\1#p" "$TILES_JS" | sort -u)"
[ -n "$HOSTS" ] || die "found no https tile host in $TILES_JS. Either the map stopped loading remote tiles - in which case delete this suite - or the line changed shape and this check went blind. Zero hosts is not zero risk."

host_count="$(printf '%s\n' "$HOSTS" | grep -c .)"
printf '\n  tiles requested from (read from %s): %s\n\n' "${TILES_JS#$ROOT/}" "$(printf '%s ' $HOSTS)"

# --- the policy blocks that serve the site --------------------------------
[ -f "$SCOPE" ] || die "$SCOPE does not exist - the scope list is what makes this check honest about which policies it read"

# Read the scope into arrays first. `while read` down a pipe runs in a
# subshell and every count it makes is lost at the closing brace.
files=(); anchors=()
while IFS=$'\t' read -r f a _rest; do
  case "$f" in ''|'#'*) continue ;; esac
  [ -n "$a" ] || die "scope row for $f has no anchor"
  files+=("$f"); anchors+=("$a")
done < "$SCOPE"

[ "${#files[@]}" -gt 0 ] || die "$SCOPE lists no policy blocks. An empty scope reads exactly like a clean one."

for i in "${!files[@]}"; do
  f="${files[$i]}"; anchor="${anchors[$i]}"
  path="$ROOT/$f"
  [ -f "$path" ] || die "$f is in the scope list and does not exist. If a server was retired, take it out of the list in the same change."

  # The anchor line, by literal match. Named, not numbered.
  start="$(grep -nF -- "$anchor" "$path" | head -1 | sed -E 's/:.*$//')"
  [ -n "$start" ] || die "anchor not found in $f: $anchor  -- the block was renamed. This suite refuses rather than report on a block it could not find."

  # The block runs from the anchor to its closing bracket. Taking the whole
  # file instead would let ANY img-src in it answer for this one - and
  # web.native.mjs holds two policies on purpose.
  block="$(awk -v s="$start" 'NR>=s { print; if (NR > s && $0 ~ /^[[:space:]]*\]/) exit }' "$path")"
  imgline="$(printf '%s\n' "$block" | grep -F 'img-src' | head -1)"

  if [ -z "$imgline" ]; then
    bad "$f: the block at '$anchor' has no img-src directive at all"
    printf '        A policy without img-src falls back to default-src, so\n'
    printf "        this may still be blocking tiles - assert it by name.\n"
    continue
  fi

  for h in $HOSTS; do
    case "$imgline" in
      *"$h"*) ok "$f: img-src permits $h" ;;
      *)      bad "$f: img-src does NOT permit $h"
              printf '        block:   %s\n' "$anchor"
              printf '        img-src: %s\n' "$(printf '%s' "$imgline" | sed -E 's/^ *//; s/,$//')"
              printf '        Every tile is blocked when this program serves the site,\n'
              printf '        whatever the console has in the map field.\n' ;;
    esac
  done
done

# --- and the header a live origin actually sends --------------------------
# Opt-in, because there is no site origin in a plain dev checkout and a
# check that silently skips itself is the failure this suite is about. When
# it is skipped it is SAID, and it is not counted as a pass.
if [ -n "$ORIGIN" ]; then
  hdr="$(curl -s -D - -o /dev/null --max-time 10 "$ORIGIN/index.html" 2>/dev/null | tr -d '\r' | grep -i '^content-security-policy:')"
  if [ -z "$hdr" ]; then
    bad "$ORIGIN sent no content-security-policy header (or did not answer)"
  else
    live="$(printf '%s' "$hdr" | tr ';' '\n' | grep -i 'img-src' | head -1)"
    if [ -z "$live" ]; then
      bad "$ORIGIN: the policy it sends has no img-src directive"
    else
      for h in $HOSTS; do
        case "$live" in
          *"$h"*) ok "$ORIGIN: served img-src permits $h" ;;
          *)      bad "$ORIGIN: served img-src does NOT permit $h"
                  printf '        served:  %s\n' "$(printf '%s' "$live" | sed -E 's/^ *//')" ;;
        esac
      done
    fi
  fi
else
  printf '  --    live header not checked (no W4_ORIGIN). The source check above\n'
  printf '        reads both programs; only the origin knows which one answers.\n'
fi

# --- verdict, always printed, and the count is part of it -----------------
printf '\n  ------------------------------------------------------------\n'
printf '  W4: %d check(s) run  ·  %d passed  ·  %d failed  ·  %d tile host(s)\n' \
       "$ran" "$pass" "$fail" "$host_count"

# A run that asserted nothing is not a run that passed - the family of
# `ng test` exiting 0 with no browser, and of the phase name that matched
# no suite.
if [ "$ran" -eq 0 ]; then
  printf '  W4 REFUSED: zero checks executed.\n\n'
  exit 1
fi

if [ "$fail" -gt 0 ]; then
  printf '  W4 FAILED - the map is blocked wherever that policy serves site/.\n\n'
  exit 1
fi
printf '  W4 PASSED\n\n'
