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

# Worker for pmap: one rustfmt invocation per file. The edition is looked up in
# the populated EDITION map (a subshell inherits it), so no directory walk here.
rustfmt_one() {
  local f=$1 edition="${EDITION[$1]:-2021}"
  if [ "$MODE" = "fix" ]; then
    env -u LD_LIBRARY_PATH rustfmt --edition "$edition" "$f"
  elif ! env -u LD_LIBRARY_PATH rustfmt --check --edition "$edition" "$f" > /dev/null 2>&1; then
    echo "rustfmt: $f (edition $edition) not formatted — run 'just rustfmt'"
    return 1
  fi
}

# LD_LIBRARY_PATH on this host carries the nix gcc/glibc (pulled in for the GPU
# and AI stacks); the rustup toolchain shim resolves its own libc against that
# value and dies with `undefined symbol: __pointer_chk_guard, version
# GLIBC_PRIVATE`, which the check then reads as "not formatted". Drop the
# variable for rustfmt so the gate reports formatting, not the loader.
#
# The edition depends on the directory only, so it is resolved once per
# directory (the walk up to the nearest Cargo.toml) and once per file kept in
# EDITION. rustfmt is then run concurrently: it is one process per file, and
# the suite's rustfmt time was almost all startup.
declare -A DIR_EDITION=()
declare -A EDITION=()
files=()
while IFS= read -r f; do
  files+=("$f")
  dir="$(dirname "$f")"
  if [ -z "${DIR_EDITION[$dir]+set}" ]; then
    DIR_EDITION[$dir]="$(edition_for "$f")"
  fi
  EDITION[$f]="${DIR_EDITION[$dir]}"
done < <(git ls-files '*.rs')

fail=0
if [ "${#files[@]}" -gt 0 ] && ! pmap -0 -- rustfmt_one < <(printf '%s\0' "${files[@]}"); then
  fail=1
fi

exit $fail
