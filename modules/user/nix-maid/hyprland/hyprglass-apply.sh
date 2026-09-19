#!/usr/bin/env bash
# Push the hyprglass settings into the running session, and check that they got
# there.
#
# Why this script exists at all: the plugin only reads its config when it is
# handed over, so anything that changes later — a switch, the Glass panel, a
# Hyprland config reload — has to be pushed again. The values live in
# ~/.config/hypr/hyprglass.json (written by the panel); when that file is absent
# the shipped defaults in the deployed hyprglass.lua are all there is.
#
# Usage:
#   hyprglass-apply                push base + overrides
#   hyprglass-apply --check        compare the running values with the file
#   hyprglass-apply --check --json same, machine-readable
# Exit status: 0 = in sync, 1 = a value differs (or the plugin is missing).
set -euo pipefail

hyprctl_bin="@hyprctl@"
plugin="@plugin@"
base="$HOME/.config/hypr/hyprglass.lua"
overrides="$HOME/.config/hypr/hyprglass.json"

check_only=0
as_json=0
watch=0
for arg in "$@"; do
  case "$arg" in
    --check) check_only=1 ;;
    --json) as_json=1 ;;
    --watch) watch=1 ;;
    *) echo "usage: hyprglass-apply [--check] [--json] [--watch]" >&2; exit 2 ;;
  esac
done

# Watchdog: the plugin loses its config whenever the compositor re-initialises
# it (a `hyprctl reload` does it, and the Lua API's `config.reloaded` event does
# not fire for that path — measured), and nothing else notices. Run by a timer:
# a cheap check, and a push only when something actually drifted.
if [ "${watch:-0}" = 1 ]; then
  "$0" --check >/dev/null 2>&1
  case "$?" in
    0) exit 0 ;;                 # in sync
    2) exit 2 ;;                 # cannot reach Hyprland: not our business here
  esac
  echo "hyprglass: settings drifted, re-applying" >&2
  "$0" >/dev/null 2>&1 || true
  exit 0
fi

# key name in the plugin : key in the JSON
keys=(
  "blur_strength:blurStrength"
  "blur_iterations:blurIterations"
  "vibrancy:vibrancy"
  "glass_opacity:glassOpacity"
  "refraction_strength:refraction"
  "chromatic_aberration:chromatic"
  "fresnel_strength:fresnel"
  "specular_strength:specular"
  "adaptive_dim:adaptiveDim"
)

state="$HOME/.cache/hyprglass-applied.json"

have_json=0
if [ -r "$overrides" ]; then
  if command -v jq >/dev/null 2>&1; then
    have_json=1
  else
    # Silently ignoring the panel's file is how the defaults got pushed over the
    # user's values; say it out loud instead.
    echo "hyprglass: jq is missing, the overrides in $overrides cannot be read" >&2
    exit 3
  fi
fi

# A user service does not inherit HYPRLAND_INSTANCE_SIGNATURE (systemd's user
# environment is not the session's), and hyprctl then prints "Couldn't connect to
# Hyprland". Treat that as its own condition: reading it as "drifted" made the
# watchdog re-apply forever without ever reaching the compositor.
reachable=1
"$hyprctl_bin" version >/dev/null 2>&1 || reachable=0
if [ "$reachable" = 0 ]; then
  if [ "$as_json" = 1 ]; then
    echo '{"reachable":false,"loaded":false,"inSync":false,"differences":[]}'
  else
    echo "hyprglass: cannot reach Hyprland (HYPRLAND_INSTANCE_SIGNATURE missing?)" >&2
  fi
  exit 2
fi

plugin_loaded() {
  "$hyprctl_bin" plugin list 2>/dev/null | grep -qi hyprglass
}

if ! plugin_loaded; then
  if [ "$check_only" = 1 ]; then
    [ "$as_json" = 1 ] && echo '{"loaded":false,"inSync":false,"differences":[]}' || echo "hyprglass is not loaded"
    exit 1
  fi
  "$hyprctl_bin" plugin load "$plugin" >/dev/null 2>&1 || true
fi

# Desired value for one plugin key, from the JSON when it is there.
desired() {
  local json_key="$1"
  if [ "$have_json" = 1 ]; then
    jq -r --arg k "$json_key" '.[$k] // empty' "$overrides"
  fi
}

# Actual value the plugin reports, numeric part only.
actual() {
  local key="$1"
  "$hyprctl_bin" getoption "plugin:hyprglass:$key" 2>/dev/null \
    | sed -n 's/.*: *//p' | head -1 | tr -dc '0-9.-'
}

if [ "$check_only" = 1 ]; then
  diffs=()
  # Reference, in order of authority: what the panel wants (the JSON), then what
  # the plugin reported after the last push (the recorded state). The order
  # matters — a recorded state that is newer than the user's intent would report
  # "in sync" for a value the panel just changed, which is the false positive that
  # made the earlier check worthless.
  if [ "$have_json" = 1 ]; then
    reference="$overrides"
  elif [ -r "$state" ]; then
    reference="$state"
  else
    reference=""
  fi
  if [ -n "$reference" ]; then
    for pair in "${keys[@]}"; do
      plugin_key="${pair%%:*}"
      json_key="${pair##*:}"
      want="$(jq -r --arg k "$json_key" '.[$k] // empty' "$reference" 2>/dev/null)"
      [ -n "$want" ] || continue
      got="$(actual "$plugin_key")"
      # numeric compare with the file's precision
      if ! awk -v a="$want" -v b="$got" 'BEGIN { exit !(a == b) }'; then
        diffs+=("$plugin_key=$got(want $want)")
      fi
    done
  fi
  if [ "${#diffs[@]}" -eq 0 ]; then
    [ "$as_json" = 1 ] && echo '{"loaded":true,"inSync":true,"differences":[]}' || echo "in sync"
    exit 0
  fi
  if [ "$as_json" = 1 ]; then
    printf '{"loaded":true,"inSync":false,"differences":[%s]}\n' "$(printf '"%s",' "${diffs[@]}" | sed 's/,$//')"
  else
    printf 'out of sync: %s\n' "${diffs[*]}"
  fi
  exit 1
fi

# ── push ─────────────────────────────────────────────────────────────────────
# The shipped defaults first: they are the baseline every override is relative to.
if [ -r "$base" ]; then
  "$hyprctl_bin" eval "
$(cat "$base")" >/dev/null 2>&1 || true
fi

if [ "$have_json" = 1 ]; then
  lua="$(jq -r '
    "hl.config({ plugin = { hyprglass = {",
    "  blur_strength = \(.blurStrength // 6),",
    "  blur_iterations = \(.blurIterations // 5),",
    "  vibrancy = \(.vibrancy // 0.5),",
    "  glass_opacity = \(.glassOpacity // 0.65),",
    "  refraction_strength = \(.refraction // 0.5),",
    "  chromatic_aberration = \(.chromatic // 0.3),",
    "  fresnel_strength = \(.fresnel // 0.3),",
    "  specular_strength = \(.specular // 0.1),",
    "  adaptive_dim = \(.adaptiveDim // 0.5),",
    "  light = { vibrancy = \(if .lightFrost then (.vibrancy // 0.5) else -1 end) },",
    "} } })"
  ' "$overrides")"
  # hyprctl eval reads a leading "--" as a flag: the leading newline keeps Lua
  # comments safe (the generated text has none, but the habit travels).
  "$hyprctl_bin" eval "
$lua" >/dev/null 2>&1 || true
fi

# Record what the plugin reports now: the next check compares against this, so a
# later drift is visible even in a session where the panel was never opened.
if command -v jq >/dev/null 2>&1; then
  mkdir -p "$(dirname "$state")"
  {
    printf '{\n'
    first=1
    for pair in "${keys[@]}"; do
      plugin_key="${pair%%:*}"
      json_key="${pair##*:}"
      value="$(actual "$plugin_key")"
      [ -n "$value" ] || continue
      [ "$first" = 1 ] || printf ',\n'
      first=0
      printf '  "%s": %s' "$json_key" "$value"
    done
    printf '\n}\n'
  } > "$state.tmp" && mv "$state.tmp" "$state"
fi

# Report the result instead of assuming it: the plugin has been observed to keep
# some values and drop others, which is exactly what nobody noticed for a while.
if [ "$as_json" = 1 ]; then
  exec "$0" --check --json
else
  exec "$0" --check
fi
