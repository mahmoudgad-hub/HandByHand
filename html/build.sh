#!/usr/bin/env bash
# =====================================================================
# بناء صفحات المعاينة + مقاطع APEX من مصادر src/
#
#   src/<name>.html  ──►  <name>.html                     (صفحة معاينة كاملة)
#                    └─►  apex-region/<name>.region.html  (محتوى Region فقط)
#
# العلامات المدعومة داخل ملفات src:
#   <!--ICONS-->            يُستبدل بـ parts/hbh-icons-sprite.html
#   <!--SIDEBAR:key-->      يُستبدل بـ parts/hbh-sidebar.html مع تفعيل data-nav="key"
#   <!--REGION-START--> .. <!--REGION-END-->   حدود ما يُنسخ إلى APEX Region
#
# التشغيل:  bash build.sh
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"

SPRITE=parts/hbh-icons-sprite.html
SIDEBAR=parts/hbh-sidebar.html
mkdir -p apex-region

built=0
for src in src/*.html; do
  name=$(basename "$src")
  out="$name"
  : > "$out"

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *'<!--ICONS-->'*)
        cat "$SPRITE" >> "$out"
        ;;
      *'<!--SIDEBAR:'*)
        key=$(printf '%s' "$line" | sed -n 's/.*<!--SIDEBAR:\([a-z0-9-]*\)-->.*/\1/p')
        sed "s|class=\"hbh-nav__item\" data-nav=\"$key\"|class=\"hbh-nav__item is-active\" aria-current=\"page\" data-nav=\"$key\"|" "$SIDEBAR" >> "$out"
        ;;
      *)
        printf '%s\n' "$line" >> "$out"
        ;;
    esac
  done < "$src"

  # مقطع APEX: ما بين علامتَي REGION فقط (بدون الشريط الجانبي وبدون الأيقونات)
  if grep -q '<!--REGION-START-->' "$out"; then
    sed -n '/<!--REGION-START-->/,/<!--REGION-END-->/p' "$out" \
      | sed '1d;$d' > "apex-region/${name%.html}.region.html"
  fi

  built=$((built + 1))
  echo "  built  $out"
done

echo "done: $built page(s)"
