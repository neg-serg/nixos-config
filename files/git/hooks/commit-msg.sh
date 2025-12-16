#!/usr/bin/env bash
set -euo pipefail
f="$1"
first_line="$(sed -n '1p' "$f" | tr -d '\r')"
# Allowed exceptions
case "$first_line" in
  Merge\ * | Revert\ * | fixup!* | squash!* | WIP:* | WIP\ *)
    exit 0
    ;;
esac
# Require one or more [scope] blocks followed by a space
if echo "$first_line" | grep -qE '^\[[^][]+\]( \[[^][]+\])*\s'; then
  exit 0
fi
echo "Commit message must start with [scope] subject" >&2
echo "Got: '$first_line'" >&2
echo "Examples: [activation] ..., [docs] ..., [features] ..., [symlinks] ..." >&2
exit 1
