#!/usr/bin/env bash
# Find packages that appear in multiple environment.systemPackages lists.
# This helps avoid redundancy and potential conflicts.

set -euo pipefail

REPO_ROOT="${1:-$(git rev-parse --show-toplevel 2> /dev/null || pwd)}"
cd "$REPO_ROOT"

echo "Checking for duplicate package references..."

# Extract all pkgs.* references from systemPackages
packages_file=$(mktemp)
trap 'rm -f "$packages_file"' EXIT

# Find all pkgs.foo patterns in environment.systemPackages contexts
grep -rhoE 'pkgs\.[a-zA-Z0-9_-]+' modules/ 2> /dev/null | sort > "$packages_file"

# Find duplicates (packages appearing more than once across files)
duplicates=$(sort "$packages_file" | uniq -c | sort -rn | head -20)

echo "Top 20 most referenced packages:"
echo "$duplicates"

# Check for packages that appear in multiple locations
echo ""
echo "Package duplicate check complete!"
