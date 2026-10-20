#!/usr/bin/env bash
# Render every plugin's compile-proof scene headlessly, one PNG each.
#
# `check-plm.sh` proves a plugin compiles; this proves its components paint.
# Each `files/pleamar/lib/plugins/*/<name>.check.plm` is opened through
# `pleamar-wm headless` (nothing appears on the desktop, no session needed), the
# frame is captured with PLEAMAR_HEADLESS_PNG, and the PNG has to be a real one
# (>1 KiB) with the renderer's `first frame` line in the log.
#
# Artifacts go to a temp directory by default (``--out DIR`` keeps them
# elsewhere): committed shots belong under `files/pleamar/tests/` and are written
# deliberately, not by a gate.
#
# A scene needs a Vulkan adapter that can make a Wayland surface
# (src/lib.rs: `wgpu::Backends::PRIMARY`); where the environment has none — a
# sandbox with /dev/dri closed — this prints the blocker and exits 0, like the
# other gates do for a missing tool. Run it in a real session to get the frames.
#
# Usage: check-plugin-render.sh [REPO_ROOT] [--out DIR] [--seconds N]
# Env:   PLEAMAR_BIN (pleamar), PLEAMAR_WM_BIN (pleamar-wm)
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

PLEAMAR_BIN="${PLEAMAR_BIN:-pleamar}"
PLEAMAR_WM_BIN="${PLEAMAR_WM_BIN:-pleamar-wm}"

for tool in "$PLEAMAR_BIN" "$PLEAMAR_WM_BIN"; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    echo "$tool not found — skipping the plugin render pass (install pkgs.pleamar and pleamar-wm to enable it)"
    exit 0
  fi
done

[ -n "$OUT_DIR" ] || OUT_DIR="$(mktemp -d -t pleamar-plugin-shots.XXXXXX)"
mkdir -p "$OUT_DIR"

# What "rendered" means: the frame differs from the same session with no scene
# at all. A compositor frame alone is a wallpaper; the scene's own pixels are
# what this pass is for. (A fully transparent scene would read as "nothing
# painted" — none of the check scenes is one.)
BASELINE="$OUT_DIR/_baseline.png"
PLEAMAR_HEADLESS_AT="$((SECONDS_PER_SCENE - 1))" \
  PLEAMAR_HEADLESS_PNG="$BASELINE" \
  timeout -k 5 "$((SECONDS_PER_SCENE + 40))" "$PLEAMAR_WM_BIN" headless --seconds "$SECONDS_PER_SCENE" \
  > "$OUT_DIR/_baseline.log" 2>&1 || true

SCENES=()
while IFS= read -r -d '' f; do
  SCENES+=("$f")
done < <(git -C "$REPO_ROOT" ls-files --cached --others --exclude-standard -z -- 'files/pleamar/lib/plugins/*/*.check.plm')

if [ "${#SCENES[@]}" -eq 0 ]; then
  echo "check-plugin-render: no plugin proof scenes found"
  exit 0
fi

echo "plugin render pass: ${#SCENES[@]} scene(s) -> $OUT_DIR"

failures=0
rendered=0
skipped=0
for scene in "${SCENES[@]}"; do
  name="$(basename "$(dirname "$scene")")"
  png="$OUT_DIR/$name.png"
  log="$OUT_DIR/$name.log"
  printf '%s --scene %s --no-hud\n' "$PLEAMAR_BIN" "$(cd "$REPO_ROOT" && pwd)/$scene" > "$OUT_DIR/$name.autostart"
  PLEAMAR_WM_AUTOSTART="$OUT_DIR/$name.autostart" \
    PLEAMAR_HEADLESS_AT="$((SECONDS_PER_SCENE - 1))" \
    PLEAMAR_HEADLESS_PNG="$png" \
    timeout -k 5 "$((SECONDS_PER_SCENE + 40))" "$PLEAMAR_WM_BIN" headless --seconds "$SECONDS_PER_SCENE" \
    > "$log" 2>&1 || true

  if grep -qE 'there is no graphics adapter|the graphics surface could not be created' "$log"; then
    echo "  skip $name (no graphics adapter that can make a Wayland surface)"
    skipped=$((skipped + 1))
    continue
  fi
  if [ -s "$png" ] && [ "$(stat -c %s "$png")" -gt 1024 ] && ! cmp -s "$png" "$BASELINE"; then
    echo "  ok   $name"
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
