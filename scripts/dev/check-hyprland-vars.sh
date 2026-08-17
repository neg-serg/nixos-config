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

# Collect all variable definitions ($name = value).
# Only hyprlang *.conf files are scanned: hyprland.lua is Lua, where any
# $var appears inside shell command strings (exec_cmd), not as a hyprlang
# variable, so it must not participate in this check.
defined_vars=$(grep -rhoE --include='*.conf' '^\$[a-zA-Z_][a-zA-Z0-9_]*\s*=' . 2> /dev/null \
  | sed 's/\s*=$//' | sort -u || true)

# Collect all variable usages ($name)
used_vars=$(grep -rhoE --include='*.conf' '\$[a-zA-Z_][a-zA-Z0-9_]*' . 2> /dev/null \
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
      '$wallbash_'*)
        # HyDE/wallbash runtime colors — filled in by the wallbash engine
        # from the active wallpaper in the HyDE hyprlock layout templates
        # (Anurati, Arfan_on_Clouds, IBM_Plex, …); never defined statically
        ;;
      '$col_border_active_base' | '$LAYOUT_PATH' | '$resolve' | '$WEATHER_LOCATION')
        # HyDE hyprlock template variables: $col_border_active_base is a
        # wallbash color, $LAYOUT_PATH is set by the HyDE layout selector,
        # $resolve.font=… is the HyDE font-resolver directive, and
        # $WEATHER_LOCATION is a shell env var consumed by the $WEATHER_CMD
        # curl call inside a cmd[] string
        ;;
      '$NAME')
        # Shell environment variable from /etc/os-release used inside a
        # cmd[] string (${PRETTY_NAME:-$NAME})
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
