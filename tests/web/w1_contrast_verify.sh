#!/usr/bin/env bash
# =====================================================================
# Hand By Hand (new) - W1: the design system's colour contrast
#
# Why this suite exists: the palette comment in hbh-shared.css already
# states the rule - the -500 brand shades are fills and do not reach
# 4.5:1, so text uses -600. That discipline was applied to teal and never
# extended to the semantic four, and eight token pairs shipped below the
# threshold on the smallest type in the system. A rule with no test is a
# rule that comes back.
#
# It follows the same five rules as tests/api/lib.sh:
#   1. The verdict ALWAYS prints. No `set -e` - a probe that dies records
#      a failure rather than taking the run with it.
#   2. A check names what it expects, not just that something is wrong.
#   3. The fixture is asserted by name, before the tests.
#   4. Exceptions live in contrast-exemptions.tsv with a written reason,
#      never inline here.
#   5. Rule checks are structural, so they catch a NEW violation and not
#      only the ones known today.
#
# It reads html/ - the design system's source - not the generated copies
# under web/*/src/styles, because scripts/sync-design.sh overwrites those
# and a fix applied to a copy disappears without a word.
#
# No dependencies: the sRGB luminance maths is awk.
# =====================================================================

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOKENS="$ROOT/html/hbh-shared.css"
EXEMPT="$(dirname "${BASH_SOURCE[0]}")/contrast-exemptions.tsv"

# The stylesheets the rule covers. html/ is the source; portal.css and
# ops.css are each app's own layer and are not synced, so they are listed
# by name rather than globbed - a new app layer must be added here on
# purpose, not inherited silently.
SHEETS=(
  "$ROOT/html/hbh-shared.css"
  "$ROOT/html/hbh-parent.css"
  "$ROOT/html/hbh-admin.css"
  "$ROOT/html/hbh-screens.css"
  "$ROOT/html/app/hbh-app.css"
  "$ROOT/web/portal/src/styles/portal.css"
  "$ROOT/web/ops/src/styles/ops.css"
)

# Component stylesheets too. The list above is hand-written, so a screen
# that grows its own .css file joined neither the contrast rules nor the
# no-literal one - which is exactly what happened: apply.css arrived with a
# dozen hex colours and this suite stayed green.
#
# globstar into the array, not a command substitution over a file list:
# this project lives under a path with a space in it, and splitting on
# whitespace here has bitten before.
shopt -s globstar nullglob
SHEETS+=("$ROOT"/web/*/src/app/**/*.css)
shopt -u globstar nullglob

# A named sheet that is not on disk is a rule that silently stops running.
# The ops.css path lost its prefix in an edit and this suite went on
# reporting a pass while checking one file fewer.
for _sheet in "${SHEETS[@]}"; do
  case "$_sheet" in *'*'*) continue ;; esac
  [ -f "$_sheet" ] || { printf '  W1 ABORT: sheet not found: %s\n\n' "$_sheet"; exit 1; }
done

PASS=0
FAIL=0
declare -a FAILURES=()

chk() { # chk <group> <name> <0|1> [detail]
  local grp="$1" name="$2" ok="$3" detail="${4:-}"
  if [ "$ok" = "0" ]; then
    PASS=$((PASS + 1))
    printf '  ok    %-8s %s\n' "$grp" "$name"
  else
    FAIL=$((FAIL + 1))
    FAILURES+=("$grp/$name: $detail")
    printf '  FAIL  %-8s %s  --  %s\n' "$grp" "$name" "$detail"
  fi
}

# --- WCAG 2.1 relative luminance and contrast ratio -------------------
# exp(2.4*log(x)) rather than x^2.4: the operator differs between awk
# implementations and this one is the same everywhere.
ratio() { # ratio <#rrggbb> <#rrggbb> -> "N.NN"
  awk -v a="$1" -v b="$2" '
    function chan(h,   v, s) {
      v = strtonum("0x" h) / 255
      if (v <= 0.03928) return v / 12.92
      s = (v + 0.055) / 1.055
      return exp(2.4 * log(s))
    }
    function lum(hex,   r, g, bl) {
      gsub(/^#/, "", hex)
      r  = chan(substr(hex, 1, 2))
      g  = chan(substr(hex, 3, 2))
      bl = chan(substr(hex, 5, 2))
      return 0.2126 * r + 0.7152 * g + 0.0722 * bl
    }
    BEGIN {
      la = lum(a); lb = lum(b)
      hi = (la > lb ? la : lb); lo = (la > lb ? lb : la)
      printf "%.2f", (hi + 0.05) / (lo + 0.05)
    }'
}

# --- token table, read from the stylesheet itself ---------------------
declare -A TOK=()
read_tokens() {
  local name value
  while IFS=$'\t' read -r name value; do
    [ -n "$name" ] && TOK["$name"]="$value"
  done < <(grep -o -- '--hbh-[a-z0-9-]*:[[:space:]]*#[0-9A-Fa-f]\{6\}' "$TOKENS" \
           | sed 's/^--//; s/:[[:space:]]*/\t/')
}

# --- declared exemptions ----------------------------------------------
declare -A EXEMPT_MIN=()
declare -A EXEMPT_WHY=()
read_exemptions() {
  local fg bg min why
  [ -f "$EXEMPT" ] || return 0
  while IFS=$'\t' read -r fg bg min why; do
    case "${fg:-}" in ''|'#'*) continue ;; esac
    EXEMPT_MIN["$fg|$bg"]="$min"
    EXEMPT_WHY["$fg|$bg"]="$why"
  done < "$EXEMPT"
}

# --- one pair ---------------------------------------------------------
pair() { # pair <fg-token> <bg-token> <min> <what>
  local fg="$1" bg="$2" min="$3" what="$4"
  local fghex="${TOK[$fg]:-}" bghex="${TOK[$bg]:-}"
  if [ -z "$fghex" ] || [ -z "$bghex" ]; then
    chk pair "$fg on $bg" 1 "token missing from $TOKENS"
    return
  fi

  local key="$fg|$bg" note=""
  if [ -n "${EXEMPT_MIN[$key]:-}" ]; then
    min="${EXEMPT_MIN[$key]}"
    note=" [exempt: ${EXEMPT_WHY[$key]}]"
  fi

  local got
  got="$(ratio "$fghex" "$bghex")"
  if awk -v g="$got" -v m="$min" 'BEGIN { exit !(g + 0.0001 >= m) }'; then
    chk pair "$fg on $bg" 0
    [ -n "$note" ] && printf '        %s ratio %s, floor %s%s\n' "$what" "$got" "$min" "$note"
  else
    chk pair "$fg on $bg" 1 "$what: ${got}:1, needs ${min}:1 ($fghex on $bghex)"
  fi
}

# Strip CSS comments so a rule reads declarations, not prose. awk rather
# than a perl one-liner: the nested quoting of an inline perl script inside
# a bash command substitution is how this function got mangled once already.
strip_css_comments() { # strip_css_comments <file>
  awk '
    {
      line = $0
      out = ""
      while (length(line) > 0) {
        if (inc) {
          p = index(line, "*/")
          if (p == 0) { line = ""; break }
          inc = 0; line = substr(line, p + 2)
        } else {
          p = index(line, "/*")
          if (p == 0) { out = out line; line = ""; break }
          out = out substr(line, 1, p - 1)
          inc = 1; line = substr(line, p + 2)
        }
      }
      print out
    }' "$1"
}

# --- structural rules -------------------------------------------------
# These are the checks that catch a violation nobody has written down yet.

rule_fill_token_as_text() {
  # A semantic fill token must never be a text colour: its -ink twin is
  # what clears 4.5:1 on the matching tint. Anchored so that
  # `border-color:` and `background-color:` do not match.
  local hits
  hits="$(grep -nE '(^|[^-])color:[[:space:]]*var\(--hbh-(success|progress|danger|info)\)' \
          "${SHEETS[@]}" 2>/dev/null || true)"
  if [ -z "$hits" ]; then
    chk rule "no fill token used as text" 0
  else
    chk rule "no fill token used as text" 1 \
      "use the -ink twin: $(echo "$hits" | head -3 | tr '\n' ' ')"
  fi
}

rule_muted_never_a_fill() {
  # --hbh-muted is darkened to #4C6069 on the premise that it is only ever
  # a text colour. The moment it becomes a background that premise, and the
  # value chosen under it, are both wrong.
  #
  # background only. fill and stroke on an inline icon ARE that glyph's own
  # colour - the same job `color` does for text - so flagging them called a
  # perfectly legitimate muted icon a violation. The premise this rule
  # protects is about GROUNDS, not paint.
  local hits
  hits="$(grep -nE '(background|background-color):[[:space:]]*var\(--hbh-muted\)' \
          "${SHEETS[@]}" 2>/dev/null || true)"
  if [ -z "$hits" ]; then
    chk rule "muted is text only, never a fill" 0
  else
    chk rule "muted is text only, never a fill" 1 \
      "$(echo "$hits" | head -3 | tr '\n' ' ')"
  fi
}

rule_no_raw_hex_in_components() {
  # The system's own rule: no hex literal outside hbh-shared.css, except
  # #fff over a coloured fill. A literal is a colour no contrast check can
  # see, so this rule is what keeps the suite meaningful.
  local sheet hits out=""
  for sheet in "${SHEETS[@]}"; do
    case "$sheet" in */hbh-shared.css) continue ;; esac
    [ -f "$sheet" ] || continue
    # Comments are stripped first. A hex inside a /* */ is prose, not a
    # colour the browser ever sees - and this rule failed on the very
    # comment that explains the rule, which is exactly the kind of false
    # positive that gets a whole suite switched off.
    hits="$(strip_css_comments "$sheet" \
            | grep -nEi '#[0-9a-f]{3,8}' \
            | grep -viE '#(fff|ffffff)' || true)"
    [ -n "$hits" ] && out="$out$sheet: $(echo "$hits" | head -2 | tr '\n' ' ')"
  done
  if [ -z "$out" ]; then
    chk rule "no hex literal outside hbh-shared.css" 0
  else
    chk rule "no hex literal outside hbh-shared.css" 1 "$out"
  fi
}

# =====================================================================
main() {
  printf '\nW1 - design system contrast\n'
  printf '  source: %s\n\n' "${TOKENS#$ROOT/}"

  # ---- fixture, asserted by name before anything reads it (rule 3) ----
  if [ -f "$TOKENS" ]; then chk fixture "token stylesheet present" 0
  else chk fixture "token stylesheet present" 1 "not found: $TOKENS"; fi

  read_tokens
  read_exemptions

  if [ "${#TOK[@]}" -gt 20 ]; then
    chk fixture "tokens parsed" 0
  else
    chk fixture "tokens parsed" 1 "only ${#TOK[@]} tokens read - parser or file changed shape"
  fi

  local t
  for t in hbh-muted hbh-success-ink hbh-progress-ink hbh-danger-ink hbh-info-ink; do
    if [ -n "${TOK[$t]:-}" ]; then chk fixture "token $t declared" 0
    else chk fixture "token $t declared" 1 "missing"; fi
  done

  printf '\n'

  # ---- body and meta text on every surface it lands on ----
  pair hbh-muted  hbh-surface      4.5 "meta lines, hints, chart labels"
  pair hbh-muted  hbh-bg           4.5 "meta text on the cream ground"
  pair hbh-muted  hbh-surface-2    4.5 "meta text on the inset surface"
  pair hbh-muted  hbh-neutral-100  4.5 "the muted badge"
  pair hbh-ink    hbh-surface      4.5 "body text"
  pair hbh-ink    hbh-bg           4.5 "body text on the ground"
  pair hbh-ink-2  hbh-surface      4.5 "secondary text"
  pair hbh-ink-2  hbh-bg           4.5 "secondary text on the ground"

  # ---- the semantic tint pairs: 11px badge text ----
  pair hbh-success-ink   hbh-success-bg   4.5 "success badge"
  pair hbh-progress-ink  hbh-progress-bg  4.5 "progress badge, outstanding balance"
  pair hbh-danger-ink    hbh-danger-bg    4.5 "error note, danger badge"
  pair hbh-info-ink      hbh-info-bg      4.5 "info badge"

  # ---- the interactive colour ----
  pair hbh-teal-600  hbh-surface   4.5 "links and primary text"
  pair hbh-teal-600  hbh-bg        4.5 "links on the ground"

  # ---- on-dark: sidebar, brand panel, video player ----
  pair hbh-on-dark    hbh-teal-900  4.5 "panel heading, dark end"
  pair hbh-on-dark    hbh-teal-600  4.5 "panel heading, light end"
  pair hbh-on-dark-2  hbh-teal-900  4.5 "panel body text, dark end"
  pair hbh-on-dark-2  hbh-teal-600  4.5 "panel body text, light end"
  pair hbh-on-dark-3  hbh-teal-600  4.5 "panel footer line, light end"
  pair hbh-on-dark-3  hbh-teal-900  4.5 "panel footer line, dark end"
  pair hbh-teal-300   hbh-teal-900  4.5 "accent on the dark sidebar"

  printf '\n'

  # ---- structural rules (rule 5) ----
  rule_fill_token_as_text
  rule_muted_never_a_fill
  rule_no_raw_hex_in_components

  # ---- the verdict ALWAYS prints (rule 1) ----
  printf '\n  ----------------------------------------\n'
  printf '  passed %d, failed %d\n' "$PASS" "$FAIL"
  if [ "$FAIL" -gt 0 ]; then
    printf '\n  failures:\n'
    local line
    for line in "${FAILURES[@]}"; do printf '    - %s\n' "$line"; done
    printf '\n  W1 FAILED\n\n'
    return 1
  fi
  printf '  W1 PASSED\n\n'
  return 0
}

main "$@"
