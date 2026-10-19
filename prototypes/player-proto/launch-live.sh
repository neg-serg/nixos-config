#!/usr/bin/env bash
# Start the player in the real session, sized like the design target.
# Fails loudly with a diagnosis instead of letting winit panic on a missing library.
#
# Every argument is forwarded to the player, so the capture flags work here directly:
#   --size=WxH        window size in logical units
#   --scale=N         pin the device scale (1 = 1x capture, 2 = 2x capture of the same
#                     logical layout); without it the monitor's scale is used
#   --shot-after=N    frame at which the run captures and then exits
# With PLAYER_DUMP_SWAPCHAIN set the run always ends by itself after the dump, so a scripted
# capture never needs an external kill.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
bin="$here/target/release/player"

if [ ! -x "$bin" ]; then
  echo "нет бинаря $bin — сначала: cargo build --release" >&2
  exit 1
fi

# The cache is a convenience only; an empty/absent file must not silently break the run.
if [ ! -s "$here/.libs" ]; then
  "$here/libs.sh" > "$here/.libs" || {
    echo "libs.sh не смог собрать пути" >&2
    exit 1
  }
fi
libs=$(cat "$here/.libs")

if ! env -u LD_LIBRARY_PATH LD_LIBRARY_PATH="$libs" python3 - << 'PYCHK' > /dev/null 2>&1
import ctypes, sys
for lib in ("libwayland-client.so.0", "libxkbcommon.so.0", "libvulkan.so.1"):
    try:
        ctypes.CDLL(lib)
    except OSError as e:
        print(f"{lib}: {e}", file=sys.stderr)
        sys.exit(1)
PYCHK
then
  echo "не грузятся библиотеки из .libs:" >&2
  env -u LD_LIBRARY_PATH LD_LIBRARY_PATH="$libs" python3 - << 'PYCHK' >&2 || true
import ctypes
for lib in ("libwayland-client.so.0", "libxkbcommon.so.0", "libvulkan.so.1"):
    try:
        ctypes.CDLL(lib)
        print(f"  ok   {lib}")
    except OSError as e:
        print(f"  FAIL {lib}: {e}")
PYCHK
  echo "попробуй пересобрать пути: rm $here/.libs && $here/libs.sh > $here/.libs" >&2
  exit 1
fi

exec env -u LD_LIBRARY_PATH LD_LIBRARY_PATH="$libs" "$bin" "$@" > /tmp/live-app.log 2>&1
