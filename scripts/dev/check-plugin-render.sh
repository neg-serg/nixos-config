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
# Usage: check-plugin-render.sh [REPO_ROOT] [--out DIR] [--seconds N]
# Env:   PLEAMAR_BIN, PLEAMAR_WM_BIN
#
# Exit: 0 all rendered (or skipped for want of a renderer), 1 a scene failed.
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
REPO_ROOT="$(repo_root "${1:-}")"
shift || true

OUT_DIR=""
SECONDS_PER_SCENE=4
while [ $# -gt 0 ]; do
  case "$1" in
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

# Which capture is available: the WM's headless session, or the live one.
HAVE_WM=0
command -v "$PLEAMAR_WM_BIN" > /dev/null 2>&1 && HAVE_WM=1
HAVE_SESSION=0
MON_X=0
MON_Y=0
MON_W=0
if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v grim > /dev/null 2>&1 && command -v hyprctl > /dev/null 2>&1; then
  geometry="$(hyprctl -j monitors 2> /dev/null | jq -r '((map(select(.focused == true))[0]) // .[0]) | "\(.x) \(.y) \(.width)"' 2> /dev/null || true)"
  if [ -n "$geometry" ]; then
    read -r MON_X MON_Y MON_W <<< "$geometry"
    HAVE_SESSION=1
  fi
fi

if [ "$HAVE_WM" -eq 0 ] && [ "$HAVE_SESSION" -eq 0 ]; then
  echo "check-plugin-render: no pleamar-wm and no capturable session — skipping (nothing to open a scene with)"
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

echo "plugin render pass: ${#SCENES[@]} scene(s) -> $OUT_DIR"

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

# A scene's own frame from the live session: the region its surface declares,
# captured once without the scene and once while it is up.
render_session() {
  local scene="$1" png="$2" log="$3" size w h region pid
  size="$(scene_size "$scene")"
  if [ -z "$size" ]; then
    echo "no surface size in the scene" > "$log"
    return 0
  fi
  read -r w h <<< "$size"
  # Four pixels of slack: shadows and rounded corners stay inside the crop.
  region="$((MON_X + (MON_W - w) / 2 - 4)),$((MON_Y - 4)) $((w + 8))x$((h + 8))"
  grim -g "$region" "$OUT_DIR/_before.png" > "$log" 2>&1 || true
  timeout -k 5 "$((SECONDS_PER_SCENE + 20))" "$PLEAMAR_BIN" --scene "$scene" --no-hud --seconds "$SECONDS_PER_SCENE" >> "$log" 2>&1 &
  pid=$!
  sleep 2
  grim -g "$region" "$png" >> "$log" 2>&1 || true
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
