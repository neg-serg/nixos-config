#!/usr/bin/env bash
# Guard: no repo-root references written as `../..` chains.
#
# These trees used to reach repo files by counting segments — 563 relative
# references at the 2026-09 level, the worst five levels deep
# (../../../../../files/mpv/hdr-auto-switch.lua). Such a path breaks when the
# file or the caller moves and says nothing about what it points at. The
# supported ways now:
#
#   config body      config.lib.neg.path / readFile / files.<…>  (or neg.rooted)
#   top-level let    let r = neg.rooted repoRoot; in r.path / r.readFile / r.find
#   package file     `paths` (neg.rooted, injected by packages/overlay.nix and
#                    filled in by neg.functions.callPkg)
#
# Rules, one per tree:
#   - modules/, hosts/: any `../` fails. `./sibling.nix` next to the file is
#     fine — it cannot drift;
#   - packages/: a single `../name` stays legal (a sibling package or patch
#     inside the packages tree, i.e. `callPackage ../swayimg { }`); what fails
#     is a reference that leaves the tree — `../../` or `./../files`;
#   - a line that must go up anyway carries `# allow-relative: <reason>` on
#     itself or on the line right before it, so the exception and its
#     justification stay together (and a prose comment can explain the why);
#   - comment text is stripped before matching, and a `#` inside a string is not
#     understood — such a line can hide its tail, so keep markers explicit.
#
# flake/, lib/ and tests/ are NOT scanned: that is where repo-relative
# references are inherent (the flake referring to its own root, a test to the
# tree it checks).
#
# Usage: check-relative-paths.sh [repo-root]
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
REPO_ROOT="$(repo_root "$@")"

cd "$REPO_ROOT"
for dir in modules hosts packages; do
  [[ -d "$dir" ]] || {
    echo "missing required directory: $REPO_ROOT/$dir" >&2
    exit 1
  }
done

echo "Checking for repo-root references written as ../.. chains..."

# Two rules, applied by path in one pass (regex literals only — no `-v`
# pattern, whose escapes gawk processes and mangles):
#   modules/**, hosts/**   any `../`;
#   packages/**            a reference leaving the tree: `../../` or `./../files`.
files=$(find modules hosts packages -name '*.nix' -type f | sort)
# shellcheck disable=SC2086 # word splitting is the point: one path per file
found=$(awk '
  {
    code = $0
    sub(/#.*/, "", code)          # drop comment text
    allowed = ($0 ~ /allow-relative:/ || prev ~ /allow-relative:/)
    strict = (FILENAME !~ /^packages\//)
    bad = strict ? (code ~ /\.\.\//) : (code ~ /\.\.\/\.\.\/|\.\/\.\.\/files/)
    if (bad && !allowed) print FILENAME ":" FNR ": " $0
    prev = $0
  }
' $files | sort)
scanned=$(($(find modules hosts -name '*.nix' -type f | wc -l) + $(find packages -name '*.nix' -type f | wc -l)))

if [[ -n "$found" ]]; then
  echo "FAIL: ${scanned} files scanned, repo-root references found:" >&2
  printf '%s\n' "$found" >&2
  echo >&2
  echo "Use config.lib.neg.path/readFile/files in a config body," >&2
  echo "neg.rooted repoRoot in a top-level let, or the injected \`paths\`" >&2
  echo "resolver in a package (see lib/README.md → Which resolver, where), or" >&2
  echo "mark the line '# allow-relative: <reason>' on itself or the line" >&2
  echo "before it if it truly must go up." >&2
  exit 1
fi

echo "OK: no repo-root references as ../.. chains (${scanned} files scanned)"
