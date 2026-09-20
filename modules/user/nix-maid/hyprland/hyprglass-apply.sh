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
  # The status is captured instead of left to `set -e`: a drifted check exits 1,
  # and the shell's error handling killed the script right there — the watchdog
  # reported "failed" every tick and never re-applied anything.
  # Resolved, not "$0": a relative invocation (a test harness, a shell that
  # sourced the file) would have the nested call looked up in PATH and fail with
  # 127, which reads exactly like "drifted" and re-applies on every tick.
  self="$(readlink -f "${BASH_SOURCE[0]}")"
  status=0
  "$self" --check >/dev/null 2>&1 || status=$?
  case "$status" in
    0) exit 0 ;;                 # in sync
    2) exit 0 ;;                 # cannot reach Hyprland: nothing to repair
  esac
  echo "hyprglass: settings drifted, re-applying" >&2
  "$self" >/dev/null 2>&1 || true
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
  # The layer keys have no home in the panel's JSON — the deployed base lua is
  # their only source — and a compositor reload resets them to the plugin's
  # defaults. Those defaults are the dangerous part: an empty namespace list means
  # "glass every layer", so the shell's bar and media card would land in the glass
  # pass and show the plugin's cached backdrop instead of Hyprland's live layer
  # blur. The nine numeric keys above stay in sync through such a reload, so this
  # check is the only thing that notices, and the push below repairs it.
  base_value() {
    [ -r "$base" ] || return 1
    sed -n "s/.*\b$1 *= *\"\([^\"]*\)\".*/\1/p" "$base" | head -1
  }

  for layer_key in namespaces exclude_namespaces; do
    want="$(base_value "$layer_key" || true)"
    [ -n "${want:-}" ] || continue
    got="$("$hyprctl_bin" getoption "plugin:hyprglass:layers:$layer_key" 2>/dev/null | sed -n 's/^str: *//p' | head -1)"
    [ "$want" = "$got" ] || diffs+=("layers:$layer_key=$got(want $want)")
  done

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

# ── custom presets ───────────────────────────────────────────────────────────
# Presets cannot come from the config file. `hl.config()` only reaches registered
# config *values*, and the `preset` keyword is unavailable in Lua-config mode
# ("keyword can't work with non-legacy parsers. Use eval." — measured in a nested
# 0.56.2), so the plugin's own Lua call is the only path. `preset()` is safe there:
# it runs through handleLuaPreset, while it is `config()` that aborts the
# compositor (forwardLuaConfig, see files/gui/hypr/hyprglass.lua).
#
#   scratch    — scratchpad windows, tagged hyprglass_preset_scratch in
#                hyprland.lua: blur_strength 16 (radius 16*12 px) with the maximum
#                of 5 gaussian passes. The global pair lives in the panel's JSON
#                (10.5/4 at the time of writing, the shipped default is 6/5), so a
#                scratchpad frosts roughly 1.5x the rest of the session.
#                adaptive_dim is zeroed here on purpose: the shader multiplies the
#                frosted colour by (1 - adaptiveDim * smoothstep(0.25, 0.55,
#                blurredLum)) (src/Shaders.hpp), i.e. the dim rides on the blurred
#                luminance, and that curve is tuned for the luminance a *normal*
#                blur compresses into 0.3-0.7. A much stronger blur averages the
#                backdrop further and pushes more content into the dim part of the
#                curve, so the heavier frost would arrive with a visible darkening
#                of the scratchpad. Zero here = the extra blur without the dim.
#   music_strong — the rmpc pane (window rule music-scratchpad in hyprland.lua):
#                blur_strength 64, i.e. 4x the scratch preset (radius 768 px
#                against 192), all 5 gaussian passes, adaptive_dim 0. It was the
#                one scratchpad whose backdrop was the whole picture (0.45 opacity
#                with nothing drawn over the frost) and at 16 the frost read as too
#                weak behind it; rmpc has since moved to the scratchpad opacity of
#                0.85 (services.nix), so the tag now sits behind a nearly opaque
#                pane. blur_strength is a plain scale (value * 12 px) with no
#                clamp: 64, 128 and 256 are all accepted, so this number is the knob
#                to turn if the frost is ever handed the pane back.
#   media-dark — removed: qs-music is no longer glassed by the plugin, so the
#                panel's now-playing card relies on Hyprland's own live layer
#                blur instead (see files/gui/hypr/hyprglass.lua).
#
# A `hyprctl reload` drops them again (the plugin re-reads its config), which is
# also what makes the nine knobs drift, so the next push restores these too.
"$hyprctl_bin" eval 'hl.plugin.hyprglass.preset("scratch", { blur_strength = 16, blur_iterations = 5, adaptive_dim = 0 })' >/dev/null 2>&1 || true
# The card's frame is the thin QML hairline (Music.qml, 1 px) — the plugin's own
# thick glowing border around the plate, so it is zeroed here: the plate keeps
# its frost and tint, the boundary is only the hairline.
"$hyprctl_bin" eval 'hl.plugin.hyprglass.preset("music_strong", { blur_strength = 64, blur_iterations = 5, adaptive_dim = 0 })' >/dev/null 2>&1 || true

# ── per-window overrides ─────────────────────────────────────────────────────
# The Glass panel keeps a list of { class, enabled, blurStrength, glassOpacity,
# adaptiveDim, tint } entries; each one becomes a custom preset here, plus the
# window rule that carries hyprglass_preset_<slug> for that class. The panel only
# owns the data — the Lua is generated from the JSON, not typed by hand, which is
# what makes it checkable at all.
#
# Two mechanics worth knowing when reading this:
#   * the plugin resolves a preset's *values* every frame, so redefining a preset
#     re-tunes windows that are already open (that is how editing an entry takes
#     effect immediately);
#   * a window's *tags* are computed when it is mapped, so the rule part only
#     reaches windows opened after the push (Hyprland does not recompute tags for
#     live windows).
# A disabled entry gets an empty preset: the chain then resolves to the theme and
# the global values, so a tag left over from earlier in the session is neutral
# instead of the preset it used to point at.
slug() { printf '%s' "$1" | tr -c 'A-Za-z0-9' '_'; }

if [ "$have_json" = 1 ]; then
  override_count="$(jq -r '(.windowOverrides // []) | length' "$overrides" 2>/dev/null || echo 0)"
  i=0
  while [ "$i" -lt "$override_count" ]; do
    entry="$(jq -c --argjson i "$i" '(.windowOverrides // [])[$i]' "$overrides")"
    i=$((i + 1))
    cls="$(printf '%s' "$entry" | jq -r '.class // empty')"
    [ -n "$cls" ] || continue
    preset_name="win_$(slug "$cls")"
    enabled="$(printf '%s' "$entry" | jq -r 'if .enabled == false then "false" else "true" end')"

    if [ "$enabled" = "true" ]; then
      preset_lua="$(printf '%s' "$entry" | jq -r --arg name "$preset_name" '
        "hl.plugin.hyprglass.preset(\"" + $name + "\", { " +
        ([ (if .blurStrength then "blur_strength = \(.blurStrength)" else empty end),
           (if .glassOpacity  then "glass_opacity = \(.glassOpacity)" else empty end),
           (if .adaptiveDim   then "adaptive_dim = \(.adaptiveDim)" else empty end),
           (if ((.tint // "") | test("^[0-9A-Fa-f]{8}$")) then "dark = { tint_color = 0x\(.tint) }" else empty end)
         ] | join(", ")) + " })"')"
      out="$("$hyprctl_bin" eval "$preset_lua" 2>&1 || true)"
      case "$out" in
        *error* | *expected*) echo "hyprglass: override $cls: $out" >&2 ;;
      esac
      "$hyprctl_bin" eval "hl.window_rule({ name = \"hyprglass-override-$preset_name\", match = { class = \"^$cls\$\" }, tag = \"+hyprglass_preset_$preset_name\" })" >/dev/null 2>&1 || true
    else
      "$hyprctl_bin" eval "hl.plugin.hyprglass.preset(\"$preset_name\", {})" >/dev/null 2>&1 || true
    fi
  done
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
