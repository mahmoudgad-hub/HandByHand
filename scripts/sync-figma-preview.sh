#!/usr/bin/env bash
# Inject figma/flow/src/*.mmd into figma/preview.html.
#
# preview.html carries a COPY of each diagram because a page opened with
# file:// may not fetch a sibling file. The copy is what the designer sees,
# and "edit both" was the instruction - which is how the copy went stale:
# the ops diagram said fourteen CRUD resources long after there were
# twenty-eight, and nobody could see the drift because both halves looked
# finished.
#
# The .mmd files are the source. This script makes the copy, so the two
# cannot disagree. Edit the .mmd, run this.
#
# Which .mmd goes into which block is not configured here - each block in
# preview.html already names its own source in `file:`, and this script
# reads that. One place to add a diagram, not two.
#
# No `for f in $(ls ...)`: this project lives under a path with a space in
# it, and word splitting kills the loop on directories that do not exist.
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT="$PWD"
PREVIEW="$ROOT/figma/preview.html"
SRCDIR="$ROOT/figma/flow/src"

[ -f "$PREVIEW" ] || { echo "missing: figma/preview.html" >&2; exit 1; }
[ -d "$SRCDIR" ]  || { echo "missing: figma/flow/src"   >&2; exit 1; }

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# awk walks preview.html. It remembers the `file:` of the block it is in,
# and when it reaches that block's `src: String.raw`, it prints the .mmd
# instead of the lines that were there.
#
# The block ends at the first line carrying a backtick after the opening
# one - the template literal closes on the last content line, not on a
# line of its own.
awk -v root="$ROOT" '
  /file: .[^ ]*\.mmd./ {
    line = $0
    if (match(line, /flow\/src\/[0-9A-Za-z._-]+\.mmd/)) {
      path = root "/figma/" substr(line, RSTART, RLENGTH)
    } else {
      path = ""
    }
    print
    next
  }

  /src: String\.raw`/ {
    if (path == "") { print; next }

    n = 0
    while ((getline l < path) > 0) { buf[++n] = l }
    close(path)
    if (n == 0) { print "sync: empty " path > "/dev/stderr"; exit 1 }

    # First content line rides on the opening backtick so the template
    # literal does not start with a newline.
    printf "    src: String.raw`%s\n", buf[1]
    for (i = 2; i < n; i++) print buf[i]
    printf "%s`\n", buf[n]

    injected++
    skipping = 1
    next
  }

  skipping {
    # Swallow the old copy. The line holding the closing backtick is the
    # last of it.
    if (index($0, "`")) { skipping = 0 }
    next
  }

  { print }

  END {
    if (injected == 0) {
      print "sync: no diagram blocks matched - preview.html shape changed?" > "/dev/stderr"
      exit 1
    }
    printf "sync: %d diagram(s) injected\n", injected > "/dev/stderr"
  }
' "$PREVIEW" > "$tmp"

# Never leave a half-written preview behind: only replace once awk exited
# clean and produced something of a believable size.
before=$(wc -c < "$PREVIEW")
after=$(wc -c < "$tmp")
if [ "$after" -lt $(( before / 2 )) ]; then
  echo "sync: refusing - output $after bytes vs $before before" >&2
  exit 1
fi

if cmp -s "$PREVIEW" "$tmp"; then
  echo "figma/preview.html already matches flow/src/*.mmd"
else
  cp "$tmp" "$PREVIEW"
  echo "figma/preview.html updated from flow/src/*.mmd"
fi
