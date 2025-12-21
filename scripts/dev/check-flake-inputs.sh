#!/usr/bin/env bash
# Check the age of flake inputs and warn about stale ones.
# This helps keep dependencies up to date.

set -euo pipefail

REPO_ROOT="${1:-$(git rev-parse --show-toplevel 2> /dev/null || pwd)}"
LOCK_FILE="$REPO_ROOT/flake.lock"
MAX_AGE_DAYS="${MAX_AGE_DAYS:-60}"

if [[ ! -f "$LOCK_FILE" ]]; then
  echo "flake.lock not found: $LOCK_FILE"
  exit 1
fi

echo "Checking flake input freshness (max age: $MAX_AGE_DAYS days)..."

now=$(date +%s)
stale_count=0

# Parse flake.lock and check lastModified timestamps
while IFS= read -r line; do
  if [[ "$line" =~ \"lastModified\":\ ([0-9]+) ]]; then
    last_modified="${BASH_REMATCH[1]}"
    age_days=$(((now - last_modified) / 86400))

    if [[ $age_days -gt $MAX_AGE_DAYS ]]; then
      ((stale_count++)) || true
    fi
  fi
done < "$LOCK_FILE"

# Get input names that are stale
echo ""
jq -r '
    .nodes | to_entries[] | 
    select(.value.locked.lastModified != null) |
    select((now - .value.locked.lastModified) > ('"$MAX_AGE_DAYS"' * 86400)) |
    "\(.key): \((now - .value.locked.lastModified) / 86400 | floor) days old"
' "$LOCK_FILE" 2> /dev/null || true

if [[ $stale_count -gt 0 ]]; then
  echo ""
  echo "WARNING: $stale_count input(s) are older than $MAX_AGE_DAYS days"
  echo "Consider running: nix flake update"
fi

echo ""
echo "Flake input freshness check complete!"
