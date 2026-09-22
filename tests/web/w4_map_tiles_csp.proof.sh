#!/usr/bin/env bash
# Run it:  bash tests/web/w4_map_tiles_csp.proof.sh tests/web/w4_map_tiles_csp.sh
#
# Prove W4 on a fixture tree. A guard seen only to pass has not been seen -
# and W4 was RED on the real tree from its first run, which proves it reads
# something but not that it would ever go green, nor that it refuses when
# it has been blinded. Both directions, every case.
#
# The fixture directory name carries a space and brackets on purpose: this
# project lives under "سطح المكتب/.../Hand By Hand(new)", and a check that
# only works on a plain /tmp path proves the path, not the check.
set -u
W4="$1"
FX="$(mktemp -d)/w4 fx(new)+"; mkdir -p "$FX"
trap 'rm -rf -- "$(dirname "$FX")"' EXIT
pass=0; fail=0

mk() {  # mk <relpath> <content>
  mkdir -p "$FX/$(dirname "$1")"
  printf '%s\n' "$2" > "$FX/$1"
}

run() {  # run [extra env assignments are set by the caller] -> OUT / RC
  OUT="$(W4_ROOT="$FX" W4_SCOPE="$FX/scope.tsv" W4_TILES_JS="$FX/site/contact-map.js" \
         W4_ORIGIN="${ORIGIN:-}" bash "$W4" 2>&1)"; RC=$?
}

check() {  # check <name> <wantrc> <must-contain>
  if [ "$RC" = "$2" ] && printf '%s' "$OUT" | grep -qF -- "$3"; then
    printf '  ok    %s\n' "$1"; pass=$((pass+1))
  else
    printf '  FAIL  %s  (rc=%s want %s, looking for: %s)\n' "$1" "$RC" "$2" "$3"
    printf '%s\n' "$OUT" | sed 's/^/          | /'
    fail=$((fail+1))
  fi
}

# The two shapes the real tree holds: an inline array (site.native.mjs) and
# a named constant (web.native.mjs). Both are reproduced, because the block
# extraction has to stop at the right closing bracket in both.
good_inline() {
  mk site.native.mjs "$(printf "%s\n" \
    "function send(res, file) {" \
    "  res.writeHead(200, {" \
    "    'content-security-policy': [" \
    "      \"default-src 'self'\"," \
    "      \"img-src 'self' data: https://tile.openstreetmap.org\"," \
    "      \"frame-ancestors 'none'\"," \
    "    ].join('; ')," \
    "  });" \
    "}")"
}
good_const() {
  mk web.native.mjs "$(printf "%s\n" \
    "const CSP = [" \
    "  \"default-src 'self'\"," \
    "  \"img-src 'self' data:\"," \
    "].join('; ');" \
    "" \
    "const CSP_STATIC = [" \
    "  \"default-src 'self'\"," \
    "  \"img-src 'self' data: https://tile.openstreetmap.org\"," \
    "].join('; ');")"
}
tiles_js() {  # tiles_js [host]
  mk site/contact-map.js "        img.src = '${1:-https://tile.openstreetmap.org}/' + zoom + '/' + col + '.png';"
}
scope() {
  printf '# fixture scope\n%s\t%s\t%s\n%s\t%s\t%s\n' \
    "site.native.mjs" "'content-security-policy': [" "inline" \
    "web.native.mjs"  "const CSP_STATIC = ["         "named" > "$FX/scope.tsv"
}

# --- 1. both policies permit the host -> PASS ----------------------------
tiles_js; good_inline; good_const; scope
run
check "both permit the tile host -> pass" 0 "W4 PASSED"
check "  and it says how many checks ran" 0 "2 check(s) run"

# --- 2. THE REAL DEFECT: the static policy drops the host -> FAIL --------
# This is the case that exists in the tree today, and the one the browser
# measurement proved: 8 tiles requested, 0 loaded, 8 blocked.
mk web.native.mjs "$(printf "%s\n" \
  "const CSP_STATIC = [" \
  "  \"default-src 'self'\"," \
  "  \"img-src 'self' data:\"," \
  "].join('; ');")"
run
check "static policy without the host -> fail" 1 "does NOT permit https://tile.openstreetmap.org"
check "  and it names the file" 1 "web.native.mjs"

# --- 3. the app policy is NOT the one asked about ------------------------
# web.native.mjs holds two policies. If the block extraction ran to the end
# of the file, the app policy's img-src could answer for the static one -
# in either direction. Here the APP policy has the host and the STATIC one
# does not: a suite reading the wrong block goes green on a blocked site.
mk web.native.mjs "$(printf "%s\n" \
  "const CSP = [" \
  "  \"img-src 'self' data: https://tile.openstreetmap.org\"," \
  "].join('; ');" \
  "" \
  "const CSP_STATIC = [" \
  "  \"img-src 'self' data:\"," \
  "].join('; ');")"
run
check "host in the app block does not excuse the static block" 1 "does NOT permit"

# --- 4. img-src removed altogether -> FAIL (not silence) -----------------
mk web.native.mjs "$(printf "%s\n" \
  "const CSP_STATIC = [" \
  "  \"default-src 'self'\"," \
  "].join('; ');")"
run
check "no img-src directive -> fail" 1 "has no img-src directive at all"

# --- 5. the anchor renamed -> ABORT, never a pass ------------------------
mk web.native.mjs "$(printf "%s\n" \
  "const CSP_SITE = [" \
  "  \"img-src 'self' data: https://tile.openstreetmap.org\"," \
  "].join('; ');")"
run
check "anchor renamed -> ABORT" 1 "anchor not found in web.native.mjs"

# --- 6. a scoped file that no longer exists -> ABORT ---------------------
good_const
rm -f "$FX/site.native.mjs"
run
check "scoped file missing -> ABORT" 1 "is in the scope list and does not exist"

# --- 7. an empty scope reads exactly like a clean one -> ABORT -----------
good_inline
printf '# nothing but comments\n' > "$FX/scope.tsv"
run
check "empty scope -> ABORT" 1 "lists no policy blocks"

# --- 8. the host list is DERIVED - so an empty derivation must refuse ----
# If the map stops loading remote tiles the suite must say so, not pass by
# asserting nothing. This is the leak-mask lesson: a pattern that can no
# longer see what it looks for goes green forever.
scope
mk site/contact-map.js "        var pin = document.createElement('div');"
run
check "no tile host found -> ABORT" 1 "found no https tile host"

# --- 9. a DIFFERENT provider is asked about by name ---------------------
# Proof that the allowlist follows the code and is not the literal
# 'tile.openstreetmap.org' typed into the suite.
tiles_js "https://tiles.example.org"
run
check "new provider -> the new host is what is demanded" 1 "does NOT permit https://tiles.example.org"

# --- 10. the live origin: unreachable is a FAIL, never a skip ------------
tiles_js; good_inline; good_const; scope
ORIGIN="http://127.0.0.1:8199" run
check "unreachable origin -> fail" 1 "sent no content-security-policy header"
unset ORIGIN

# --- 11. and with no origin given, the skip is SAID ---------------------
run
check "no origin -> skip is printed, not hidden" 0 "live header not checked"

printf '\n  w4 proof: %d ok, %d failed\n\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
