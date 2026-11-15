#!/usr/bin/env bash
# Parse-check every tracked shell script with osh -n (the bash-compatible
# parser from Oils, https://oils.pub). Keeps the shell corpus runnable as a
# drop-in under osh: a syntax-level bashism that osh rejects fails the lint
# suite. Runtime-only incompatibilities are NOT caught by -n (e.g. bare
# associative-array keys, OILS-ERR-101) — keep those out by convention and
# quote associative-array keys (`assoc["$key"]`).
#
# Usage: bash scripts/dev/check-osh-syntax.sh [REPO_ROOT]

set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
REPO_ROOT="$(repo_root "${1:-}")"
cd "$REPO_ROOT"

if ! command -v osh > /dev/null 2>&1; then
  echo "WARNING: osh not found; skipping OSH syntax check" >&2
  exit 0
fi

# Worker for pmap: parse one file and print the first 5 diagnostics of a
# failure. pmap replays the blocks in input order.
osh_one() {
  local file=$1 output
  if ! output=$(osh -n "$file" 2>&1); then
    printf 'ERROR: %s\n' "$file"
    printf '%s\n' "$output" | head -5
    printf '\n'
    return 1
  fi
}

fail=0
# Only files that declare a POSIX/Bash shebang — the same filter as the lint
# step in Justfile, but covering extensionless scripts too.
#
# The first line is read with the `read` builtin rather than `head | grep`:
# this loop walks every tracked file (thousands of them) and one fork pair per
# file was most of the gate's runtime. The pattern mirrors the old grep's
# `\b` (a non-word character, or end of line, must follow `sh`).
shells=()
while IFS= read -r -d '' file; do
  first=""
  IFS= read -r first < "$file" || true
  if [[ $first =~ ^#![[:space:]]*/(usr/)?bin/(env[[:space:]]+)?(ba)?sh([^A-Za-z0-9_]|$) ]]; then
    shells+=("$file")
  fi
done < <(git ls-files -z -- .)

# osh is a per-file parser with a noticeable startup cost; parse the corpus
# concurrently and let pmap put the failures back in tree order.
if [ "${#shells[@]}" -gt 0 ]; then
  if ! pmap -0 -- osh_one < <(printf '%s\0' "${shells[@]}"); then
    fail=1
  fi
fi

echo "Checked ${#shells[@]} shell script(s) with osh -n"
if [[ $fail -ne 0 ]]; then
  echo "FAILED: osh parse errors found (see above)"
  exit 1
fi
echo "All shell scripts parse under osh!"
