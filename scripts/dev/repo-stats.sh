#!/usr/bin/env bash
# Emit the README "By The Numbers" values, or verify them with --check.
#
# The table is hand-written (README.md "📊 Project Statistics"), so it drifted:
# at 778e1cf it claimed 502 Nix files / 319 module files / 107 packages while
# the tree had 609 / 355 / 143. `just lint` runs --check, so a count change is a
# lint failure instead of a silent lie.
#
# Usage: repo-stats.sh [--check] [repo-root]
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

mode=print
if [ "${1:-}" = "--check" ]; then
  mode=check
  shift
fi
REPO_ROOT="$(repo_root "$@")"
cd "$REPO_ROOT"

nix_files=$(git ls-files -- '*.nix' | wc -l)
module_files=$(git ls-files -- 'modules' | grep -c '\.nix$' || true)
domains=$(
  for dir in modules/*/; do
    [ -f "$dir/default.nix" ] && printf '%s\n' "$dir"
  done | wc -l
)
commits=$(git rev-list --count HEAD)

# The flake surface is 143 attributes; custom-packages.nix itself has 137
# entries, the other six come from packages/flake/default.nix.
packages=""
if command -v nix > /dev/null 2>&1 && command -v jq > /dev/null 2>&1; then
  packages=$(
    nix eval --json "$REPO_ROOT#packages.x86_64-linux" --apply builtins.attrNames \
      | jq length
  )
fi

keys=(
  "Module Domains"
  "Nix Files"
  "Custom Packages"
  "Module Files"
  "Total Commits"
)
# "Total Commits" is printed but deliberately not checked: every commit
# increments the count, so a README that says N is stale the moment the next
# commit exists. A pre-commit lint has no fixed point to satisfy; the README
# uses a "5200+" marker instead.
check_keys=(
  "Module Domains"
  "Nix Files"
  "Custom Packages"
  "Module Files"
)
declare -A stats=(
  ["Module Domains"]="$domains"
  ["Nix Files"]="$nix_files"
  ["Custom Packages"]="$packages"
  ["Module Files"]="$module_files"
  ["Total Commits"]="$commits"
)

if [ "$mode" = print ]; then
  for key in "${keys[@]}"; do
    printf '%-16s %s\n' "$key" "${stats[$key]}"
  done
  exit 0
fi

fail=0
for key in "${check_keys[@]}"; do
  expected=${stats[$key]}
  if [ -z "$expected" ]; then
    echo "repo-stats: cannot compute '$key' (nix/jq missing?)" >&2
    fail=1
    continue
  fi
  actual=$(grep -oP "^\| \*\*${key}\*\* \| \K[0-9]+" README.md || true)
  if [ -z "$actual" ]; then
    echo "repo-stats: README.md has no '**$key**' row" >&2
    fail=1
  elif [ "$actual" != "$expected" ]; then
    echo "repo-stats: $key: README says $actual, tree has $expected" >&2
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "README statistics: FAILED (run 'just stats' and update the table)" >&2
  exit 1
fi
echo "README statistics: OK"
