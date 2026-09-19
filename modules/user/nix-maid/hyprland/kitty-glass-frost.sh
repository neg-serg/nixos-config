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
# The slice is rendered at 1/scale of the pane's physical rect (scale = the
# largest power of two that leaves a canvas ~480 px wide) and kitty scales it back
# up on the GPU: blurring 480x270 instead of 2688x864 is a fraction of the work for
# the same picture. A gaussian of sigma 120/scale covers the same area as sigma
# 120 at 1:1, and kitty's bilinear upscale of the result is indistinguishable
# from the full-resolution pipeline (measured on the pane's slice: RMSE 0.0006,
# ~0.16/255). The pane therefore has to be launched with a scaling
# background_image_layout (cscaled, see hyprland/services.nix).
#
# The 1/scale canvas is cached per (wallpaper, mtime, scale, monitor) as
# ~/.cache/kitty-glass-frost/canvas-*.png, so a wallpaper that has been shown
# before costs a crop plus a 3 KB PNG instead of a full decode.
#
# Knobs without a rebuild:
#   ~/.config/kitty/glass-frost-blur   gaussian sigma, physical px (120)
#   ~/.config/kitty/glass-frost-dim    brightness multiplier (0.15)
#
# Usage:
#   kitty-glass-frost <class>          push the slice once (pane start)
#   kitty-glass-frost --watch <class>  re-push it on every wallpaper change and
#                                      on every knob edit, until the pane exits
#
# --watch exists because the slice is baked into the pane's background image:
# nothing repaints it when the wallpaper changes, so without the watcher the pane
# stays frozen on the wallpaper it was started with until it is restarted (see
# the launcher in hyprland/services.nix).
#
# $1: window class of the pane (or --watch, then the class). Silently does
# nothing when the wallpaper, the geometry or kitty's remote control is
# unavailable — the pane then simply keeps its plain background.
set -uo pipefail

mode=once
case "${1:-}" in
  --watch)
    mode=watch
    shift
    ;;
esac

class="${1:-}"
[ -n "$class" ] || exit 0

hyprctl_bin="@hyprctl@"
[ -x "$hyprctl_bin" ] || hyprctl_bin="hyprctl"
kitten_bin="@kitten@"
[ -x "$kitten_bin" ] || kitten_bin="kitten"
command -v magick > /dev/null 2>&1 || exit 0
command -v jq > /dev/null 2>&1 || exit 0

frost() {
  blur="$(head -n1 "$HOME/.config/kitty/glass-frost-blur" 2> /dev/null | tr -d '[:space:]')"
  case "$blur" in '' | *[!0-9]*) blur=120 ;; esac
  dim="$(head -n1 "$HOME/.config/kitty/glass-frost-dim" 2> /dev/null | tr -d '[:space:]')"
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
  [ -n "$geom" ] || return 0
  read -r px py pw ph <<< "$geom"

  mon="$("$hyprctl_bin" monitors -j 2> /dev/null | jq -r '.[0] | "\(.width) \(.height) \(.scale)"')"
  read -r mw mh mscale <<< "$mon"
  [ -n "${mw:-}" ] && [ "$mw" -gt 0 ] || return 0

  wallpaper="$(head -n1 "$HOME/.cache/quickshell-wallpaper-path" 2> /dev/null | tr -d '[:space:]')"
  [ -n "$wallpaper" ] && [ -r "$wallpaper" ] || return 0

  # Render at 1/$scale and let kitty scale it back up (see the header): the
  # canvas is ~480 px wide whatever the monitor, so the blur and the encode work
  # on ~1/30 of the pixels of the pane rect.
  scale=1
  while [ "$((mw / (scale * 2)))" -ge 480 ]; do scale="$((scale * 2))"; done
  cwp="$((mw / scale))"
  chp="$((mh / scale))"
  blur_scaled="$(awk -v b="$blur" -v k="$scale" 'BEGIN { printf "%.2f", b / k }')"

  # Decoding and downscaling the wallpaper is what costs, so keep the canvas
  # around: switching between wallpapers already seen is then a crop and a 3 KB
  # PNG (~25 ms against ~0.7 s for the full decode-and-blur of a 4K file).
  cache="$HOME/.cache/kitty-glass-frost"
  mkdir -p "$cache" 2> /dev/null
  stamp="$(stat -c '%Y-%s' "$wallpaper" 2> /dev/null || printf '0')"
  key="$(printf '%s %s %s %sx%s' "$wallpaper" "$stamp" "$scale" "$cwp" "$chp" | cksum | cut -d' ' -f1)"
  canvas="$cache/canvas-$scale-$key.png"
  if [ ! -s "$canvas" ]; then
    candidate="$cache/canvas-$scale-$key.$$.png"
    # jpeg:size lets libjpeg decode at a fraction of the file's resolution
    # instead of handing a 4K-8K bitmap to the resize.
    if magick -define "jpeg:size=${cwp}x${chp}" "$wallpaper" \
      -resize "${cwp}x${chp}^" -gravity center -extent "${cwp}x${chp}" \
      -define png:compression-level=1 "$candidate" 2> /dev/null && [ -s "$candidate" ]; then
      mv -f "$candidate" "$canvas" 2> /dev/null || canvas="$candidate"
      # Keep the handful of canvases the session actually switches between, not
      # the whole collection.
      ls -t "$cache"/canvas-*.png 2> /dev/null | tail -n +9 | xargs -r rm -f 2> /dev/null
    else
      rm -f "$candidate" 2> /dev/null
      return 0
    fi
  fi

  # Logical geometry -> the pane's rect in canvas pixels, clamped to the canvas:
  # the scratchpad daemon may restore a pane that hangs over a screen edge, and a
  # crop reaching outside the image would come out the wrong size.
  #
  # The crop below must run without -gravity, which is why it happens in a second
  # magick invocation: under a gravity, IM shifts a crop that carries +X+Y offsets
  # by half the crop size, and that is how the slice used to land half a pane away
  # from the pane's own rect (the frost showed the bottom-right of the wallpaper
  # for a pane sitting in the middle of the screen).
  read -r kx ky kw kh <<< "$(awk -v s="$mscale" -v x="$px" -v y="$py" -v w="$pw" -v h="$ph" -v mw="$mw" -v mh="$mh" -v k="$scale" '
  BEGIN {
    cx = x * s; cy = y * s; cw = w * s; ch = h * s;
    if (cx < 0) { cw += cx; cx = 0 }
    if (cy < 0) { ch += cy; cy = 0 }
    if (cx + cw > mw) cw = mw - cx
    if (cy + ch > mh) ch = mh - cy
    if (cw < 1 || ch < 1) { cx = 0; cy = 0; cw = mw; ch = mh }
    kw = int(cw / k + 0.5); kh = int(ch / k + 0.5)
    kx = int(cx / k + 0.5); ky = int(cy / k + 0.5)
    if (kx + kw > int(mw / k)) kx = int(mw / k) - kw
    if (ky + kh > int(mh / k)) ky = int(mh / k) - kh
    if (kx < 0) kx = 0
    if (ky < 0) ky = 0
    printf "%d %d %d %d", kx, ky, kw, kh
  }')"

  out="$HOME/.cache/kitty-glass-frost-$class.png"
  magick "$canvas" \
    -crop "${kw}x${kh}+${kx}+${ky}" +repage \
    -blur "0x${blur_scaled}" -evaluate multiply "$dim" \
    "$out" 2> /dev/null || return 0
  [ -s "$out" ] || return 0

  # KITTY_LISTEN_ON is inherited from the pane we are running inside.
  if [ -n "${KITTY_LISTEN_ON:-}" ]; then
    "$kitten_bin" @ --to "$KITTY_LISTEN_ON" set-background-image "$out" > /dev/null 2>&1 || true
  fi
  return 0
}

# Re-push the slice whenever one of the three files that describe it changes:
# wl's notify file, wl's state (the fallback source of the slice) and the frost
# knobs. inotify rather than a poll — the pane lives for hours, and polling for it
# is the same waste the per-window layout daemon was replaced over.
watch_loop() {
  command -v inotifywait > /dev/null 2>&1 || return 0
  parent="$PPID"
  wallpaper_path="$HOME/.cache/quickshell-wallpaper-path"
  while kill -0 "$parent" 2> /dev/null; do
    if [ ! -e "$wallpaper_path" ]; then
      # Nothing to watch yet; wait for wl to write the file.
      sleep 5
      continue
    fi
    # Exit status: 0 = an event arrived, 1 = error, 2 = the timeout expired.
    if inotifywait -qq -t 60 \
      -e modify -e close_write -e create -e moved_to \
      "$wallpaper_path" \
      "$HOME/.config/kitty" \
      "$HOME/.local/state/wl" 2> /dev/null; then
      kill -0 "$parent" 2> /dev/null || return 0
      frost
    else
      sleep 1
    fi
  done
}

case "$mode" in
  watch) watch_loop ;;
  *) frost ;;
esac
exit 0
