#!/usr/bin/env bash
set -euo pipefail

# Allow skipping in CI or when committing legacy upstream docs
if [[ "${SKIP_MARKDOWN_CHECK:-}" == "1" ]]; then
  exit 0
fi

# Policy (hard rule, see AGENTS.md):
# - Documentation is English-only. Russian and Chinese characters are not
#   allowed in ANY Markdown file in this repo (no *.ru.md variants either).
# - Fails the commit: language violations are errors, not warnings.

shopt -s nullglob

# Allowlisted files may contain literal Cyrillic glyphs as CONTENT EXAMPLES
# (Russian keyboard-layout characters in keysym/duplicate tables). Prose in
# these files is still English; no Russian documentation is allowed.
GLYPH_ALLOWLIST="docs/howto/hotkeys-ru-layout.md docs/howto/swayimg-hotkeys.md"

fail=0
while IFS= read -r -d '' file; do
  if [[ -L "$file" ]]; then
    continue
  fi
  rel="${file#./}"
  case " $GLYPH_ALLOWLIST " in
    *" $rel "*) continue ;;
  esac
  for re in "[\x{0400}-\x{04FF}]" "[\x{4E00}-\x{9FFF}]"; do
    if LC_ALL=C.UTF-8 grep -P "$re" -n -- "$file" > /dev/null 2>&1; then
      kind=Cyrillic
      [[ "$re" == *4E00* ]] && kind=Chinese
      echo "Markdown language policy violation: $kind found in $file" >&2
      LC_ALL=C.UTF-8 grep -P "$re" -n -- "$file" | head -n 5 >&2 || true
      fail=1
    fi
  done
done < <(find . -name '*.md' -print0)

if [[ $fail -ne 0 ]]; then
  echo "Markdown language policy: FAILED (English-only docs; no Cyrillic/CJK in *.md)" >&2
  exit 1
fi

echo "Markdown language policy: OK"
