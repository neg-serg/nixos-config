#!/usr/bin/env bash
# Measure the bar against Quickshell, pixel by pixel.
#
# 1. captures the live bar strip (the bottom `panelHeight * scale` band of the
#    focused monitor) — this is Quickshell, the reference;
# 2. opens the pleamar bar scene over the same strip for a few seconds and
#    captures it again;
# 3. reports the difference (mean, percent of pixels changed) and writes a
#    side-by-side (qs | pleamar | diff) so the difference can be looked at.
#
# The parity standard is Quickshell's own geometry, so both frames are the same
# region of the same monitor at the same scale: the diff is the whole answer.
#
# Usage: parity-bar.sh [REPO_ROOT] [--out DIR] [--scene FILE] [--seconds N]
#                      [--strip PX] [--approve]
#   --approve   approve the bar scene's plugins first (`pleamar --approve`), so
#               the data-driven parts (cover, analyser, MPD flags, dB) are live.
#               Without it the plugins run with no permissions: the chrome is
#               still drawn, the content is not.
#
# Exit: 0 measured (whatever the number), 1 the frames could not be taken.
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
REPO_ROOT="$(repo_root "${1:-}")"
shift || true

OUT_DIR=""
SCENE="files/pleamar/shells/bar/bar.plm"
SECONDS_TO_RUN=6
STRIP=""
APPROVE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --out)
      OUT_DIR="${2:?--out needs a directory}"
      shift 2
      ;;
    --scene)
      SCENE="${2:?--scene needs a file}"
      shift 2
      ;;
    --seconds)
      SECONDS_TO_RUN="${2:?--seconds needs a number}"
      shift 2
      ;;
    --strip)
      STRIP="${2:?--strip needs a number}"
      shift 2
      ;;
    --approve)
      APPROVE=1
      shift
      ;;
    *)
      echo "parity-bar: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [ -z "${PLEAMAR_BIN:-}" ]; then
  PLEAMAR_BIN="$(resolve_pleamar_tool pleamar "$REPO_ROOT" || true)"
fi
if [ -z "$PLEAMAR_BIN" ]; then
  echo "parity-bar: pleamar not found (no PATH entry and no flake output)" >&2
  exit 1
fi
for tool in grim hyprctl magick; do
  command -v "$tool" > /dev/null 2>&1 || {
    echo "parity-bar: $tool is not on PATH — it needs a live Hyprland session and ImageMagick" >&2
    exit 1
  }
done
[ -n "${WAYLAND_DISPLAY:-}" ] || {
  echo "parity-bar: WAYLAND_DISPLAY is not set — run it from the session that shows the bar" >&2
  exit 1
}

[ -n "$OUT_DIR" ] || OUT_DIR="$(mktemp -d -t pleamar-parity.XXXXXX)"
mkdir -p "$OUT_DIR"
REPO_ABS="$(cd "$REPO_ROOT" && pwd)"

# The monitor the bar is on: the focused one, with its geometry and scale.
monitor_line="$(hyprctl monitors 2> /dev/null | awk '
  BEGIN { RS = ""; FS = "\n" }
  /focused: yes/ {
    name = $1; sub(/^Monitor /, "", name); sub(/ .*/, "", name)
    size = ""; scale = "1"
    for (i = 1; i <= NF; i++) {
      if ($i ~ / at /) { size = $i; sub(/^[[:space:]]*/, "", size); sub(/@.*/, "", size) }
      if ($i ~ /^[[:space:]]*scale:/) { scale = $i; sub(/^[[:space:]]*scale:[[:space:]]*/, "", scale) }
    }
    print name, size, scale
    exit
  }' || true)"
[ -n "$monitor_line" ] || {
  echo "parity-bar: hyprctl sees no focused monitor" >&2
  exit 1
}
read -r MON_NAME MON_SIZE MON_SCALE <<< "$monitor_line"
MON_W="${MON_SIZE%x*}"
MON_H_LOG="${MON_SIZE#*x}"

# The bar strip: the QS bar is `panelHeight * scale` tall (22 * scale) plus its
# hotzone below it; the pleamar bar surface is 44 design px in the same place.
if [ -z "$STRIP" ]; then
  STRIP="$(awk -v s="$MON_SCALE" 'BEGIN { printf "%d", 22 * s + 12 }')"
fi
# Physical pixels for the crop: grim with -o reports the output's own pixels.
PHYS_H="$(awk -v h="$MON_H_LOG" -v s="$MON_SCALE" 'BEGIN { printf "%d", h * s + 0.5 }')"
Y="$((PHYS_H - STRIP))"
REGION="0,$Y ${MON_W}x${STRIP}"

echo "parity-bar: monitor $MON_NAME, ${MON_W}×${PHYS_H} @${MON_SCALE}x, strip ${STRIP}px -> $OUT_DIR"

capture() {
  grim -o "$MON_NAME" -g "$REGION" "$1" 2> /dev/null || grim -o "$MON_NAME" "$1" 2> /dev/null
}

capture "$OUT_DIR/qs.png" || {
  echo "parity-bar: grim could not capture $MON_NAME" >&2
  exit 1
}

if [ "$APPROVE" -eq 1 ]; then
  "$PLEAMAR_BIN" --approve "$REPO_ABS/$SCENE" --yes > "$OUT_DIR/approve.log" 2>&1 || true
fi

"$PLEAMAR_BIN" --scene "$REPO_ABS/$SCENE" --no-hud --seconds "$SECONDS_TO_RUN" > "$OUT_DIR/scene.log" 2>&1 &
pid=$!
sleep 3
capture "$OUT_DIR/plm.png" || true
wait "$pid" 2> /dev/null || true

[ -s "$OUT_DIR/qs.png" ] && [ -s "$OUT_DIR/plm.png" ] || {
  echo "parity-bar: the pleamar bar did not come up; see $OUT_DIR/scene.log" >&2
  exit 1
}

# Same geometry for both, whatever each capture really measured.
magick "$OUT_DIR/qs.png" -resize "${MON_W}x${STRIP}!" "$OUT_DIR/qs-fit.png"
magick "$OUT_DIR/plm.png" -resize "${MON_W}x${STRIP}!" "$OUT_DIR/plm-fit.png"

mean="$(magick "$OUT_DIR/qs-fit.png" "$OUT_DIR/plm-fit.png" -compose difference -composite -colorspace gray -format '%[fx:mean]' info: 2> /dev/null)"
# Pixels that differ by more than 8/255: the "visible" share.
share="$(magick "$OUT_DIR/qs-fit.png" "$OUT_DIR/plm-fit.png" -compose difference -composite -colorspace gray -threshold 3% -format '%[fx:mean]' info: 2> /dev/null)"
magick "$OUT_DIR/qs-fit.png" "$OUT_DIR/plm-fit.png" -compose difference -composite "$OUT_DIR/diff.png"
magick "$OUT_DIR/qs-fit.png" "$OUT_DIR/plm-fit.png" "$OUT_DIR/diff.png" -append "$OUT_DIR/stack.png"

printf 'parity-bar: mean difference %.5f, visible share %.2f%% (qs | pleamar | diff: %s/stack.png)\n' \
  "$mean" "$(awk -v s="$share" 'BEGIN { printf "%.2f", s * 100 }')" "$OUT_DIR"
