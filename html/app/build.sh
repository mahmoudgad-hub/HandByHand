#!/usr/bin/env bash
# بناء نموذج بوابة ولي الأمر: src/index.html -> index.html
# العلامة <!--ICONS--> تُستبدل بمصدر الأيقونات الوحيد في ../parts/
set -euo pipefail
cd "$(dirname "$0")"
SPRITE=../parts/hbh-icons-sprite.html
: > index.html
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    *'<!--ICONS-->'*) cat "$SPRITE" >> index.html ;;
    *) printf '%s\n' "$line" >> index.html ;;
  esac
done < src/index.html
echo "built index.html ($(wc -l < index.html) lines)"
