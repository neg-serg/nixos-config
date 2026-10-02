#!/usr/bin/env bash
# Guard: no `../` in the config tree (modules/ and hosts/).
#
# Those two trees used to reach repo files by counting `../..` segments — 563
# relative references, the worst five levels deep
# (../../../../../files/mpv/hdr-auto-switch.lua). Such a path breaks when the
# file or the caller moves and says nothing about what it points at. The
# supported ways now:
#
#   config body    config.lib.neg.path / readFile / files.<…>   (or neg.rooted)
#   top-level let  let r = neg.rooted repoRoot; in r.path / r.readFile / r.find
#   package file   the sibling `callPackage ../name` (packages/ is not scanned)
#
# Rules:
#   - `../` in a .nix line of modules/ or hosts/ fails;
#   - `./sibling.nix` next to the file is fine — it cannot drift;
#   - a line that must go up carries `# allow-relative: <reason>` on itself or
#     on the line right before it, so the exception and its justification stay
#     together (and a prose comment can explain the why);
#   - comment text is stripped before matching, and a `#` inside a string is not
#     understood — such a line can hide its tail, so keep markers explicit.
#
# flake/, packages/, lib/ and tests/ are NOT scanned: that is where
# repo-relative references are inherent (the flake referring to the repo root, a
# package to its sibling patch, a test to the tree it checks).
#
# Usage: check-relative-paths.sh [repo-root]
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
REPO_ROOT="$(repo_root "$@")"

cd "$REPO_ROOT"
for dir in modules hosts; do
  [[ -d "$dir" ]] || {
    echo "missing required directory: $REPO_ROOT/$dir" >&2
    exit 1
  }
done

echo "Checking for relative ../ paths in modules/ and hosts/..."

files=$(find modules hosts -name '*.nix' -type f | sort)
count=$(printf '%s\n' "$files" | wc -l)

# shellcheck disable=SC2086 # word splitting is the point: one path per file
found=$(awk '
  {
    code = $0
    sub(/#.*/, "", code)          # drop comment text
    allowed = ($0 ~ /allow-relative:/ || prev ~ /allow-relative:/)
    if (code ~ /\.\.\// && !allowed) {
      print FILENAME ":" FNR ": " $0
    }
    prev = $0
  }
' $files | sort)

if [[ -n "$found" ]]; then
  echo "FAIL: ${count} files scanned, relative ../ paths found:" >&2
  printf '%s\n' "$found" >&2
  echo >&2
  echo "Use config.lib.neg.path/readFile/files in a config body, or" >&2
  echo "neg.rooted repoRoot in a top-level let (see lib/README.md →" >&2
  echo "By name, not by path), or mark the line" >&2
  echo "'# allow-relative: <reason>' on the line (or the line before) if it" >&2
  echo "truly must go up." >&2
  exit 1
fi

echo "OK: modules/ and hosts/ hold no relative ../ paths (${count} files scanned)"
