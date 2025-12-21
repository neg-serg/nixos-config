#!/usr/bin/env bash
# Verify all $variable references in Hyprland config files are defined.
# This catches typos like $nonexistent_var that would fail silently.

set -euo pipefail

REPO_ROOT="${1:-$(git rev-parse --show-toplevel 2> /dev/null || pwd)}"
HYPR_DIR="$REPO_ROOT/files/gui/hypr"

if [[ ! -d "$HYPR_DIR" ]]; then
  echo "Hyprland config directory not found: $HYPR_DIR"
  exit 0
fi

cd "$HYPR_DIR"

echo "Checking Hyprland variable definitions..."

# Collect all variable definitions ($name = value)
defined_vars=$(grep -rhoE '^\$[a-zA-Z_][a-zA-Z0-9_]*\s*=' . 2> /dev/null \
  | sed 's/\s*=$//' | sort -u || true)

# Collect all variable usages ($name)
used_vars=$(grep -rhoE '\$[a-zA-Z_][a-zA-Z0-9_]*' . 2> /dev/null \
  | grep -v '^\$HOME' \
  | grep -v '^\$USER' \
  | grep -v '^\$XDG_' \
  | grep -v '^\$HYPRLAND_' \
  | sort -u || true)

errors=0
for var in $used_vars; do
  # Check if this variable is defined
  if ! echo "$defined_vars" | grep -qxF "$var"; then
    # Skip known builtins
    case "$var" in
      '$mainMod' | '$S' | '$M' | '$A' | '$C' | '$SM' | '$SA' | '$SC' | '$SAM')
        # Common Hyprland modifiers
        ;;
      '$TIME' | '$LAYOUT' | '$FAIL' | '$ATTEMPTS')
        # Hyprlock variables
        ;;
      *)
        echo "WARNING: Variable $var used but not defined"
        ((errors++)) || true
        ;;
    esac
  fi
done

if [[ $errors -gt 0 ]]; then
  echo ""
  echo "Found $errors undefined variable(s)"
  # Don't fail - just warn
fi

echo "Hyprland variable check complete!"
