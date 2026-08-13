#!/usr/bin/env bash
# Format or check Rust files with the edition from their nearest Cargo.toml.
# Run without args to check, with --fix to format in place.
set -euo pipefail

REPO_ROOT="${1:-$(git rev-parse --show-toplevel 2> /dev/null || pwd)}"
MODE="${2:-check}"

cd "$REPO_ROOT"

edition_for() {
  local dir
  dir="$(dirname "$1")"
  while [ "$dir" != "$REPO_ROOT" ]; do
    if [ -f "$dir/Cargo.toml" ]; then
      grep -m1 '^edition' "$dir/Cargo.toml" 2> /dev/null | sed 's/.*"\(.*\)".*/\1/' | tr -d ' '
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  echo "2021"
}

fail=0
while IFS= read -r f; do
  edition="$(edition_for "$f")"
  if [ "$MODE" = "fix" ]; then
    rustfmt --edition "$edition" "$f"
  elif ! rustfmt --check --edition "$edition" "$f" > /dev/null 2>&1; then
    echo "rustfmt: $f (edition $edition) not formatted — run 'just rustfmt'"
    fail=1
  fi
done < <(git ls-files '*.rs')

exit $fail
