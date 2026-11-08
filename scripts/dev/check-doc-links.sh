#!/usr/bin/env bash
# Guard: relative links in tracked Markdown must resolve.
#
# docs/ was removed in 778e1cf ("Keep documentation out of the published tree")
# while README.md and AGENTS.md kept pointing into it. A link to a missing file
# is indistinguishable from a deliberate one until someone clicks it, so every
# `](target)` that is not http(s)/mailto/anchor-only is resolved against the
# file's directory and a miss fails the check.
#
# Usage: check-doc-links.sh [repo-root]
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
REPO_ROOT="$(repo_root "$@")"

cd "$REPO_ROOT"

fail=0
checked=0
while IFS= read -r -d '' file; do
  dir=$(dirname "$file")
  while IFS= read -r target; do
    path=${target%%#*}
    [ -z "$path" ] && continue
    case "$path" in
      http://* | https://* | mailto:* | '<'* | '#'*) continue ;;
      *'<'* | *'*'* | *'$'* | *'{'*) continue ;; # templated/pseudo links
    esac
    checked=$((checked + 1))
    case "$path" in
      /*) resolved="$REPO_ROOT$path" ;;
      *) resolved="$dir/$path" ;;
    esac
    if [ ! -e "$resolved" ]; then
      echo "Broken markdown link: $file -> $target" >&2
      fail=1
    fi
  done < <(grep -oP '\]\(\K[^)]+' -- "$file" 2> /dev/null || true)
done < <(git ls-files -z -- '*.md')

if [ "$fail" -ne 0 ]; then
  echo "Markdown link guard: FAILED" >&2
  exit 1
fi
echo "Markdown link guard: OK ($checked relative links)"
