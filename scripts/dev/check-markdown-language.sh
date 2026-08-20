#!/usr/bin/env bash
set -euo pipefail

# Allow skipping in CI or when committing legacy upstream docs
if [[ "${SKIP_MARKDOWN_CHECK:-}" == "1" ]]; then
  exit 0
fi

# Policy:
# - English docs live in *.md
# - Russian docs must live in *.ru.md
# - No Chinese (CJK) characters anywhere in Markdown (hard rule from root AGENTS.md)
# Warn-only: prints offenders, never aborts under `set -euo pipefail`.

shopt -s nullglob

fail=0
while IFS= read -r -d '' file; do
  if [[ -L "$file" ]]; then
    continue
  fi
  # CJK check applies to ALL markdown, including *.ru.md
  if LC_ALL=C.UTF-8 grep -P "[\x{4E00}-\x{9FFF}]" -n -- "$file" > /dev/null 2>&1; then
    echo "Markdown language policy violation: Chinese (CJK) found in $file" >&2
    LC_ALL=C.UTF-8 grep -P "[\x{4E00}-\x{9FFF}]" -n -- "$file" | head -n 5 >&2 || true
    fail=1
  fi
  case "$file" in
    *.ru.md) continue ;;
  esac
  if LC_ALL=C.UTF-8 grep -P "[\x{0400}-\x{04FF}]" -n -- "$file" > /dev/null 2>&1; then
    echo "Markdown language policy violation: Cyrillic found in $file" >&2
    LC_ALL=C.UTF-8 grep -P "[\x{0400}-\x{04FF}]" -n -- "$file" | head -n 5 >&2 || true
    fail=1
  fi
done < <(find . -name '*.md' -print0)

if [[ $fail -ne 0 ]]; then
  echo -e "\nWarning: language policy violations found (Cyrillic in non-*.ru.md, or CJK anywhere)." >&2
fi

echo "Markdown language policy: OK"
