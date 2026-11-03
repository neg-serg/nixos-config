#!/usr/bin/env bash
# One monitor, four numbers that all look like "the screen".
#
# On this host the panel is 3840×2160 at Hyprland scale 2, so a single output has
# a device size, a compositor entry with a scale, a logical size, and the design
# reference a scene's lengths were tuned on. Pasting a number from the wrong
# column is a scene four times too big, a wallpaper with black bands, or a login
# screen shifted by half a panel: a `kind: lock` surface declared `size: full,
# full` is a 0×0 box, the engine centres that box on the monitor, and the scene
# then paints from the monitor's centre (fixed by packages/overlays/
# pleamar-lock-full.patch — the face prints `box`, `face` and `from` in the log).
#
# This prints each monitor once and then names, for every consumer, which number
# it takes. It reads the live compositor and never a constant, so it is right
# after a mode change as well. Run it before writing a size into a scene, and
# again when a log line's numbers look wrong.
#
# Usage: screen-numbers.sh
# Exit status: 1 when there is no compositor (or no jq) to ask, 0 otherwise.
set -euo pipefail

command -v hyprctl > /dev/null 2>&1 || {
  echo "screen-numbers: no hyprctl — a Hyprland session is what this reads" >&2
  exit 1
}
command -v jq > /dev/null 2>&1 || {
  echo "screen-numbers: jq is needed to read hyprctl monitors" >&2
  exit 1
}

monitors="$(hyprctl monitors -j 2> /dev/null || true)"
# A session that is not Hyprland's monitor list: `hyprctl` fails, or answers with a
# plain word, and jq would report a parse error two lines later instead of this.
if ! printf '%s' "$monitors" | jq -e 'type == "array" and length > 0' > /dev/null 2>&1; then
  echo "screen-numbers: hyprctl monitors did not answer with a list of monitors." >&2
  echo "  Run it inside the Hyprland session (HYPRLAND_INSTANCE_SIGNATURE must name it)." >&2
  exit 1
fi

# The picture behind a lock screen, when the theme pipeline has one published:
# its own shape is what decides whether a declared cell can hold it.
wallpaper="$(head -1 "$HOME/.cache/pleamar/wallpaper-path" 2> /dev/null || true)"

identify_size() {
  command -v magick > /dev/null 2>&1 || return 1
  magick identify -format '%w %h' "$1" 2> /dev/null
}

while IFS=$'\t' read -r name model width height scale logical refresh focused; do
  logical_w="${logical%×*}"
  logical_h="${logical#*×}"
  # The frozen per-monitor scale of INTERFACES.md §3.2 with the spec's `ui` 1.15:
  # what a library component multiplies its design lengths by.
  now="$(awk -v u=1.15 -v w="$logical_w" -v h="$logical_h" \
    'BEGIN { s = u * ((w / 1920) < (h / 1080) ? (w / 1920) : (h / 1080)); if (s < 0.8) s = 0.8; if (s > 1.5) s = 1.5; printf "%.3f", s }')"
  printf '\n%s · %s · %s Hz%s\n\n' "$name" "$model" "$refresh" "$focused"
  printf '  %-31s %s\n' "framebuffer, buffers, grim" "$width × $height  (device px)"
  printf '  %-31s %s\n' "Hyprland monitor entry" "$width × $height  (device px, scale $scale)"
  printf '  %-31s %s\n' "logical (device ÷ scale)" "$logical_w × $logical_h"
  printf '  %-31s %s\n' "a scene's screen.width/height" "$logical_w × $logical_h  (logical, never the framebuffer)"
  printf '  %-31s %s\n' "a lock face's configure size" "$logical_w × $logical_h  (logical; \`size: full, full\` is this box)"
  printf '  %-31s %s\n' "a lock face's buffers" "$width × $height  (device px = face × scale)"
  printf '  %-31s %s\n' "scaleNow (INTERFACES §3.2)" "$now  (ui 1.15 × clamp(min(w/1920, h/1080), 0.8, 1.5))"
  printf '  %-31s %s\n' "1 design px" "$now logical px, $(awk -v n="$now" -v s="$scale" 'BEGIN { printf "%.2f", n * s }') device px"
  if [ -n "$wallpaper" ] && [ -f "$wallpaper" ]; then
    if size="$(identify_size "$wallpaper")"; then
      read -r wall_w wall_h <<< "$size"
      printf '  %-31s %s\n' "the wallpaper a scene draws" "$(basename "$wallpaper") · $wall_w × $wall_h ($(awk -v w="$wall_w" -v h="$wall_h" 'BEGIN { printf "%.2f", w / h }'):1)"
      printf '  %-31s %s\n' "its cell" "declare \`0, 0\` (the file's own shape); a fixed 16:9 cell leaves black bands"
    fi
  fi
done < <(printf '%s' "$monitors" | jq -r '.[] | [
  .name,
  ((.make // "") + " " + (.model // "") | sub("^ +| +$"; "")),
  (.width | tostring),
  (.height | tostring),
  (.scale | tostring),
  (((.width / .scale) | floor | tostring) + "×" + (((.height / .scale) | floor) | tostring)),
  (.refreshRate | floor | tostring),
  (if .focused then " · focused" else "" end)
] | @tsv')

cat << 'LEGEND'

The names, once (so a pasted number can be checked instead of felt):

  device px     what the panel has: buffers, grim, a screenshot, Hyprland's width/height.
                Never what a scene draws its lengths in.
  scale         the compositor's (here 2). It is not a scene's number: a scene's
                surface is already in logical px.
  logical px    device ÷ scale. What `screen.width`/`screen.height` measure and what
                every `at:`, `size:` and `from:` in a scene is in.
  design px     the scene language's own unit, tuned on 1920×1080 logical (design.width
                and design.height). `scaleNow` turns design px into logical px.
  image cell    `image x = from p, W, H`: W×H is the texture's size AND the shape the
                picture is fitted into. A shape that is not the picture's own leaves
                black bands baked into the texture; `0, 0` takes the file's own shape.

A lock screen is the one place where two of these meet: the face is configured in
logical px and paints buffers in device px, and the engine centres its declared box
on the monitor. `size: full, full` is the monitor itself (pleamar-lock-full.patch);
before that patch it was a 0×0 box, so the scene's origin sat at the monitor's centre
and the whole login screen was painted half a panel away. `/tmp/pleamar-login-layer.log`
carries the face's own line — `box … , face … , from 0,0` — and `from` is the answer.
LEGEND
