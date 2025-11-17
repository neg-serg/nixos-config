#!/usr/bin/env bash
set -euo pipefail

# Allow skipping in CI or when committing legacy upstream docs
if [[ "${SKIP_MARKDOWN_CHECK:-}" == "1" ]]; then
  exit 0
fi

# Policy:
# - English docs live in *.md
# - Russian docs must live in *.ru.md
# This check fails if any non-*.ru.md Markdown contains Cyrillic characters.

shopt -s nullglob

fail=0
while IFS= read -r -d '' file; do
  case "$file" in
    *.ru.md) continue;;
  esac
  if LC_ALL=C.UTF-8 grep -P "[\x{0400}-\x{04FF}]" -n -- "$file" >/dev/null 2>&1; then
    echo "Markdown language policy violation: Cyrillic found in $file" >&2
    # Show offending lines (up to first 5 for brevity)
    LC_ALL=C.UTF-8 grep -P "[\x{0400}-\x{04FF}]" -n -- "$file" | head -n 5 >&2
    fail=1
  fi
done < <(find . -type f -name "*.md" -print0)

if [[ $fail -ne 0 ]]; then
  echo "\nFix: move Russian content to a corresponding *.ru.md file." >&2
  exit 1
fi

echo "Markdown language policy: OK"
