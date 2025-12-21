#!/usr/bin/env bash
# Find packages that appear in multiple environment.systemPackages lists.
# This helps avoid redundancy and potential conflicts.

set -eu

REPO_ROOT="${1:-$(git rev-parse --show-toplevel 2> /dev/null || pwd)}"
cd "$REPO_ROOT"

echo "Checking for duplicate package references..."

# Extract all pkgs.* references from modules
packages_file=$(mktemp)
trap 'rm -f "$packages_file"' EXIT

# Find all pkgs.foo patterns
grep -rhoE 'pkgs\.[a-zA-Z0-9_-]+' modules/ 2> /dev/null | sort > "$packages_file" || true

# Find duplicates (packages appearing more than once)
echo "Top 20 most referenced packages:"
sort "$packages_file" 2> /dev/null | uniq -c | sort -rn 2> /dev/null | head -20 || true

echo ""
echo "Package duplicate check complete!"
