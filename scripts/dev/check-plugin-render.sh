#!/usr/bin/env bash
# Render every plugin's compile-proof scene, one PNG each.
#
# `check-plm.sh` proves a plugin compiles; this proves its components paint.
# Each `files/pleamar/lib/plugins/*/<name>.check.plm` is opened and the frame is
# captured, then compared against the same frame *without* the scene: a
# compositor's own wallpaper is not proof that a plugin drew anything.
#
# Two ways to get a frame, in order:
#   pleamar-wm headless   nothing appears on the desktop (PLEAMAR_HEADLESS_PNG);
#   the ambient session   the scene opens over the desktop for a few seconds and
#                         `grim` captures the region its surface declares
#                         (Hyprland only). It is what a host without pleamar-wm
#                         uses.
#
# The binary itself comes from PATH, or from the flake (`nix build .#pleamar
# --option substitute false`): the shell's package is not installed while
# `features.gui.pleamar` is off, and this gate brings its own.
#
# A scene needs a Vulkan adapter that can make a Wayland surface (src/lib.rs:
# `wgpu::Backends::PRIMARY`); where the environment has none — a sandbox with
# /dev/dri closed — every scene is skipped with that reason, never failed.
#
# Artifacts go to a temp directory by default (`--out DIR` keeps them): committed
# shots belong under `files/pleamar/tests/`, written deliberately, not by a gate.
#
# Usage: check-plugin-render.sh [REPO_ROOT] [--out DIR] [--seconds N] [--probe]
#        --probe prints what the gate found (binary, session, capture tools) and
#        exits: that is the first thing to run when a scene is skipped.
# Env:   PLEAMAR_BIN, PLEAMAR_WM_BIN
#
# Exit: 0 all rendered (or skipped for want of a renderer), 1 a scene failed.
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
REPO_ROOT="$(repo_root "${1:-}")"
shift || true

OUT_DIR=""
SECONDS_PER_SCENE=4
PROBE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --probe)
      PROBE=1
      shift
      ;;
    --out)
      OUT_DIR="${2:?--out needs a directory}"
      shift 2
      ;;
    --seconds)
      SECONDS_PER_SCENE="${2:?--seconds needs a number}"
      shift 2
      ;;
    *)
      echo "check-plugin-render: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

PLEAMAR_WM_BIN="${PLEAMAR_WM_BIN:-pleamar-wm}"
if [ -z "${PLEAMAR_BIN:-}" ]; then
  PLEAMAR_BIN="$(resolve_pleamar_tool pleamar "$REPO_ROOT" || true)"
fi
if [ -z "$PLEAMAR_BIN" ]; then
  echo "pleamar not found — skipping the plugin render pass (no PATH entry and no flake output)"
  exit 0
fi

[ -n "$OUT_DIR" ] || OUT_DIR="$(mktemp -d -t pleamar-plugin-shots.XXXXXX)"
mkdir -p "$OUT_DIR"
REPO_ABS="$(cd "$REPO_ROOT" && pwd)"

# Which capture is available: the WM's headless session, or the live one. The
# live one needs a Wayland session, grim, ImageMagick and a Hyprland that answers
# `hyprctl monitors`; every miss is named, so a skip is actionable.
HAVE_WM=0
command -v "$PLEAMAR_WM_BIN" > /dev/null 2>&1 && HAVE_WM=1

HAVE_SESSION=0
MON_NAME="${PLEAMAR_RENDER_MONITOR:-}"
SESSION_PROBLEM=""
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
  SESSION_PROBLEM="WAYLAND_DISPLAY is not set"
elif ! command -v grim > /dev/null 2>&1; then
  SESSION_PROBLEM="grim is not on PATH"
elif ! command -v hyprctl > /dev/null 2>&1; then
  SESSION_PROBLEM="hyprctl is not on PATH (not a Hyprland session?)"
elif ! command -v magick > /dev/null 2>&1; then
  SESSION_PROBLEM="ImageMagick (magick) is not on PATH"
else
  # The focused monitor's name and size, from the text form: `hyprctl monitors`
  # prints one paragraph per monitor, `focused: yes` in the one in use.
  monitor_line="$(hyprctl monitors 2> /dev/null | awk '
    BEGIN { RS = ""; FS = "\n" }
    /focused: yes/ {
      name = $1; sub(/^Monitor /, "", name); sub(/ .*/, "", name)
      size = ""
      for (i = 1; i <= NF; i++) if ($i ~ / at /) { size = $i; sub(/^[[:space:]]*/, "", size); sub(/@.*/, "", size) }
      print name, size
      exit
    }' || true)"
  if [ -z "$monitor_line" ]; then
    SESSION_PROBLEM="hyprctl sees no focused monitor (HYPRLAND_INSTANCE_SIGNATURE / XDG_RUNTIME_DIR?)"
  else
    [ -n "$MON_NAME" ] || MON_NAME="${monitor_line%% *}"
    HAVE_SESSION=1
  fi
fi

if [ "$PROBE" -eq 1 ]; then
  echo "render probe:"
  echo "  pleamar     $PLEAMAR_BIN"
  echo "  pleamar-wm  $(command -v "$PLEAMAR_WM_BIN" 2> /dev/null || echo '(not found)')"
  echo "  wayland     ${WAYLAND_DISPLAY:-'(not set)'}"
  echo "  grim        $(command -v grim 2> /dev/null || echo '(not found)')"
  echo "  hyprctl     $(command -v hyprctl 2> /dev/null || echo '(not found)')"
  echo "  magick      $(command -v magick 2> /dev/null || echo '(not found)')"
  if [ "$HAVE_SESSION" -eq 1 ]; then
    echo "  session     monitor $MON_NAME"
  else
    echo "  session     unusable: $SESSION_PROBLEM"
  fi
  exit 0
fi

if [ "$HAVE_WM" -eq 0 ] && [ "$HAVE_SESSION" -eq 0 ]; then
  echo "check-plugin-render: no pleamar-wm and no capturable session — skipping ($SESSION_PROBLEM)"
  exit 0
fi

SCENES=()
while IFS= read -r -d '' f; do
  SCENES+=("$f")
done < <(git -C "$REPO_ABS" ls-files --cached --others --exclude-standard -z -- 'files/pleamar/lib/plugins/*/*.check.plm')

if [ "${#SCENES[@]}" -eq 0 ]; then
  echo "check-plugin-render: no plugin proof scenes found"
  exit 0
fi

echo "plugin render pass: ${#SCENES[@]} scene(s) -> $OUT_DIR (monitor ${MON_NAME:-headless wm})"

# The declared surface of a check scene: `surface { size: W, H; … }`.
scene_size() {
  sed -n 's/.*size:[[:space:]]*\([0-9][0-9]*\),[[:space:]]*\([0-9][0-9]*\).*/\1 \2/p' "$1" | head -n 1
}

# A scene's own frame via pleamar-wm headless, straight to a PNG.
render_headless() {
  local scene="$1" png="$2" log="$3"
  printf '%s --scene %s --no-hud\n' "$PLEAMAR_BIN" "$scene" > "$OUT_DIR/autostart"
  PLEAMAR_WM_AUTOSTART="$OUT_DIR/autostart" \
    PLEAMAR_HEADLESS_AT="$((SECONDS_PER_SCENE - 1))" \
    PLEAMAR_HEADLESS_PNG="$png" \
    timeout -k 5 "$((SECONDS_PER_SCENE + 40))" "$PLEAMAR_WM_BIN" headless --seconds "$SECONDS_PER_SCENE" \
    > "$log" 2>&1 || true
}

# One monitor's frame, cropped to the box a scene declares at its top centre:
# a scene anchored `top` sits there, and the crop keeps the desktop's own
# animation out of the comparison.
capture_monitor() {
  local png="$1" w="$2" h="$3" full="$OUT_DIR/_full.png" fw fh x y
  if ! grim -o "$MON_NAME" "$full" > /dev/null 2>&1; then
    grim "$full" > /dev/null 2>&1 || return 1
  fi
  read -r fw fh <<< "$(magick identify -format '%w %h' "$full" 2> /dev/null || echo 0 0)"
  [ "${fw:-0}" -gt 0 ] || return 1
  x=$(((fw - w) / 2))
  y=$(((fh - h) / 2))
  [ "$y" -lt 0 ] && y=0
  # Four pixels of slack each way: shadows and rounded corners stay inside.
  x=$((x - 4))
  [ "$x" -lt 0 ] && x=0
  magick "$full" -crop "$((w + 8))x$((h + 8))+$x+$y" +repage "$png" > /dev/null 2>&1
}

# A scene's own frame from the live session: the same crop once without the
# scene and once while it is up.
render_session() {
  local scene="$1" png="$2" log="$3" size w h pid
  size="$(scene_size "$scene")"
  if [ -z "$size" ]; then
    echo "no surface size in the scene" > "$log"
    return 0
  fi
  read -r w h <<< "$size"
  capture_monitor "$OUT_DIR/_before.png" "$w" "$h" || echo "grim could not capture $MON_NAME" > "$log"
  timeout -k 5 "$((SECONDS_PER_SCENE + 20))" "$PLEAMAR_BIN" --scene "$scene" --no-hud --seconds "$SECONDS_PER_SCENE" >> "$log" 2>&1 &
  pid=$!
  sleep 2
  capture_monitor "$png" "$w" "$h" >> "$log" 2>&1 || true
  wait "$pid" || true
}

# How much two frames differ: 0 (the same) .. 1 (nothing alike).
frame_delta() {
  magick "$1" "$2" -compose difference -composite -colorspace gray -format '%[fx:mean]' info: 2> /dev/null || echo 0
}

failures=0
rendered=0
skipped=0
for scene in "${SCENES[@]}"; do
  name="$(basename "$(dirname "$scene")")"
  file="$REPO_ABS/$scene"
  png="$OUT_DIR/$name.png"
  log="$OUT_DIR/$name.log"

  if [ "$HAVE_WM" -eq 1 ]; then
    render_headless "$file" "$png" "$log"
    if [ -s "$png" ] && ! grep -q 'the graphics surface could not be created\|there is no graphics adapter' "$log"; then
      echo "  ok   $name (headless)"
      rendered=$((rendered + 1))
      continue
    fi
    if [ "$HAVE_SESSION" -eq 0 ]; then
      echo "  skip $name (no graphics adapter that can make a Wayland surface)"
      skipped=$((skipped + 1))
      continue
    fi
  fi

  render_session "$file" "$png" "$log"
  if grep -q 'there is no graphics adapter\|the graphics surface could not be created' "$log"; then
    echo "  skip $name (no graphics adapter that can make a Wayland surface)"
    skipped=$((skipped + 1))
    continue
  fi
  if [ -s "$png" ] && [ -s "$OUT_DIR/_before.png" ] \
    && awk -v d="$(frame_delta "$OUT_DIR/_before.png" "$png")" 'BEGIN { exit !(d > 0.0002) }'; then
    echo "  ok   $name (session)"
    rendered=$((rendered + 1))
    continue
  fi
  echo "  FAIL $name — see $log"
  sed -n '1,20p' "$log" | sed 's/^/       /'
  failures=$((failures + 1))
done

if [ "$failures" -gt 0 ]; then
  echo "FAILED: $failures of ${#SCENES[@]} plugin scene(s) did not render"
  exit 1
fi
if [ "$rendered" -eq 0 ]; then
  echo "OK: nothing failed; $skipped scene(s) skipped for want of a graphics adapter — run this in a real session"
  exit 0
fi
echo "OK: $rendered rendered, $skipped skipped — shots in $OUT_DIR"
