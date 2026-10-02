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
# Rules: no `../` in modules/, hosts/ or packages/. `./sibling.nix` next to the
# file stays fine — it cannot drift — and a package is reached by name
# (`neg.functions.pkg "swayimg"`, `paths.path "packages/…"`) instead of by
# counting levels up to it.
#   - a line that must go up anyway carries `# allow-relative: <reason>` on
#     itself or on the line right before it, so the exception and its
#     justification stay together (and a prose comment can explain the why);
#   - a file whose `../` all belong to something embedded (a build script
#     operating on the unpacked source tree) carries
#     `# allow-relative-file: <reason>` and is skipped entirely — the file is
#     listed in the output, so the exemption stays visible;
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

# One rule, one pass (regex literal — no `-v` pattern, whose escapes gawk
# processes and mangles).
files=$(find modules hosts packages -name '*.nix' -type f | sort)
scanned=$(printf '%s\n' "$files" | wc -l)

# Files that opted out wholesale (see the header), subtracted before scanning.
exempt=$(grep -rl 'allow-relative-file:' $files 2> /dev/null || true)
# shellcheck disable=SC2086 # word splitting is the point: one path per file
[[ -n "$exempt" ]] && files=$(grep -L 'allow-relative-file:' $files)
# shellcheck disable=SC2086 # word splitting is the point: one path per file
found=$(awk '
  {
    code = $0
    sub(/#.*/, "", code)          # drop comment text
    allowed = ($0 ~ /allow-relative:/ || prev ~ /allow-relative:/)
    if (code ~ /\.\.\// && !allowed) print FILENAME ":" FNR ": " $0
    prev = $0
  }
' $files | sort)

if [[ -n "$found" ]]; then
  echo "FAIL: ${scanned} files scanned, repo-root references found:" >&2
  printf '%s\n' "$found" >&2
  echo >&2
  echo "Use config.lib.neg.path/readFile/files in a config body," >&2
  echo "neg.rooted repoRoot in a top-level let, or in a package" >&2
  echo "neg.functions.pkg \"name\" / paths.path (see lib/README.md →" >&2
  echo "Which resolver, where), or" >&2
  echo "mark the line '# allow-relative: <reason>' on itself or the line" >&2
  echo "before it if it truly must go up." >&2
  exit 1
fi

for f in $exempt; do
  echo "  exempt (allow-relative-file): $f"
done
echo "OK: no repo-root references as ../.. chains (${scanned} files scanned)"
