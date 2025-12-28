#!/usr/bin/env bash
set -euo pipefail

# This script checks if any files present in the directory match .gitignore patterns.
# It uses 'fd' which respects .gitignore files by default.
# It compares "all files present" vs "files fd sees (non-ignored)".
# Any difference represents files that are present (tracked) but ignored -> ERROR.

if ! command -v fd &> /dev/null; then
  echo "Error: 'fd' is required for this check."
  exit 1
fi

echo "Checking for tracked files that match .gitignore..."

# Create temp files for comparison
ALL_FILES=$(mktemp)
ALLOWED_FILES=$(mktemp)
trap 'rm -f "$ALL_FILES" "$ALLOWED_FILES"' EXIT

# 1. List all files currently in the directory (recursively)
# Normalize paths to start with ./ for consistent sorting
find . -type f | sort > "$ALL_FILES"

# 2. List files that are NOT ignored by .gitignore
# --type f: files only
# --hidden: include hidden files (dotfiles)
# --no-ignore-vcs: still respect .gitignore, but don't look for global git settings (safer in sandbox)
# actually regular `fd` respects .gitignore in the current dir.
fd --type f --hidden . | sort > "$ALLOWED_FILES"

# 3. Find files in ALL_FILES that are NOT in ALLOWED_FILES
# comm -23: lines unique to file 1
IGNORED_BUT_TRACKED=$(comm -23 "$ALL_FILES" "$ALLOWED_FILES")

if [[ -n "$IGNORED_BUT_TRACKED" ]]; then
  echo "ERROR: The following files are tracked (present) but match .gitignore patterns:"
  echo "$IGNORED_BUT_TRACKED"
  echo ""
  echo "These files should be removed from git or the .gitignore rules adjusted."
  exit 1
fi

echo "Success: No ignored files are currently tracked."
