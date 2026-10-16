#!/usr/bin/env bash
# Format or check Rust files with the edition from their nearest Cargo.toml.
# Run without args to check, with --fix to format in place.
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
REPO_ROOT="$(repo_root "${1:-}")"
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
# LD_LIBRARY_PATH on this host carries the nix gcc/glibc (pulled in for the GPU
# and AI stacks); the rustup toolchain shim resolves its own libc against that
# value and dies with `undefined symbol: __pointer_chk_guard, version
# GLIBC_PRIVATE`, which the check then reads as "not formatted". Drop the
# variable for rustfmt so the gate reports formatting, not the loader.
while IFS= read -r f; do
  edition="$(edition_for "$f")"
  if [ "$MODE" = "fix" ]; then
    env -u LD_LIBRARY_PATH rustfmt --edition "$edition" "$f"
  elif ! env -u LD_LIBRARY_PATH rustfmt --check --edition "$edition" "$f" > /dev/null 2>&1; then
    echo "rustfmt: $f (edition $edition) not formatted — run 'just rustfmt'"
    fail=1
  fi
done < <(git ls-files '*.rs')

exit $fail
