#!/usr/bin/env bash
# Frost for a glass scratchpad pane: a heavily blurred, darkened slice of the
# current wallpaper, pushed into the pane as kitty's background image.
#
# Why at the pane and not in the compositor: nothing on that side moves this
# window's blur any more. Measured with a high-frequency backdrop behind the open
# pane, the hyprglass window presets (blur_strength 1 vs 16, plus a per-window
# override pushed from the Glass panel) and Hyprland's own decoration:blur:size
# (26 vs 90, both set before the window mapped) all leave the frost bit-identical,
# so the only knob left is the pane's own background.
#
# The slice comes from the wallpaper because that is what the pane's frost shows
# anyway (the compositor blurs the wallpaper — xray), and `wl` fits the wallpaper
# to the output with `crop`: the pane's screen rect maps into the image the same
# way, by covering the screen and cutting the rect out.
#
# Knobs without a rebuild:
#   ~/.config/kitty/glass-frost-blur   gaussian sigma, physical px (120)
#   ~/.config/kitty/glass-frost-dim    brightness multiplier (0.15)
#
# $1: window class of the pane. Silently does nothing when the wallpaper, the
# geometry or kitty's remote control is unavailable — the pane then simply keeps
# its plain background.
set -uo pipefail

class="${1:-}"
[ -n "$class" ] || exit 0

hyprctl_bin="@hyprctl@"
[ -x "$hyprctl_bin" ] || hyprctl_bin="hyprctl"
kitten_bin="@kitten@"
[ -x "$kitten_bin" ] || kitten_bin="kitten"
command -v magick >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

blur="$(head -n1 "$HOME/.config/kitty/glass-frost-blur" 2>/dev/null | tr -d '[:space:]')"
case "$blur" in '' | *[!0-9]*) blur=120 ;; esac
dim="$(head -n1 "$HOME/.config/kitty/glass-frost-dim" 2>/dev/null | tr -d '[:space:]')"
case "$dim" in '' | *[!0-9.]*) dim=0.15 ;; esac

# The pane maps a moment after the terminal starts, so wait for its geometry.
geom=""
for _ in $(seq 1 40); do
  geom="$(
    "$hyprctl_bin" clients -j 2> /dev/null \
      | jq -r --arg c "$class" '.[] | select(.class == $c) | "\(.at[0]) \(.at[1]) \(.size[0]) \(.size[1])"' \
      | head -n1
  )"
  [ -n "$geom" ] && break
  sleep 0.2
done
[ -n "$geom" ] || exit 0
read -r px py pw ph <<< "$geom"

mon="$("$hyprctl_bin" monitors -j 2> /dev/null | jq -r '.[0] | "\(.width) \(.height) \(.scale)"')"
read -r mw mh mscale <<< "$mon"
[ -n "${mw:-}" ] && [ "$mw" -gt 0 ] || exit 0

wallpaper="$(head -n1 "$HOME/.cache/quickshell-wallpaper-path" 2> /dev/null | tr -d '[:space:]')"
[ -n "$wallpaper" ] && [ -r "$wallpaper" ] || exit 0

# Logical geometry -> physical pixels of the wallpaper canvas, clamped to the
# canvas: the scratchpad daemon may restore a pane that hangs over a screen edge,
# and a crop reaching outside the image would come out the wrong size.
read -r cx cy cw ch <<< "$(awk -v s="$mscale" -v x="$px" -v y="$py" -v w="$pw" -v h="$ph" -v mw="$mw" -v mh="$mh" '
  BEGIN {
    cx = x * s; cy = y * s; cw = w * s; ch = h * s;
    if (cx < 0) { cw += cx; cx = 0 }
    if (cy < 0) { ch += cy; cy = 0 }
    if (cx + cw > mw) cw = mw - cx
    if (cy + ch > mh) ch = mh - cy
    if (cw < 1 || ch < 1) { cx = 0; cy = 0; cw = mw; ch = mh }
    printf "%d %d %d %d", cx, cy, cw, ch
  }')"

out="$HOME/.cache/kitty-glass-frost-$class.png"
magick "$wallpaper" \
  -resize "${mw}x${mh}^" -gravity center -extent "${mw}x${mh}" \
  -crop "${cw}x${ch}+${cx}+${cy}" +repage \
  -blur "0x${blur}" -evaluate multiply "$dim" \
  "$out" 2> /dev/null || exit 0
[ -s "$out" ] || exit 0

# KITTY_LISTEN_ON is inherited from the pane we are running inside.
if [ -n "${KITTY_LISTEN_ON:-}" ]; then
  "$kitten_bin" @ --to "$KITTY_LISTEN_ON" set-background-image "$out" > /dev/null 2>&1 || true
fi
exit 0
