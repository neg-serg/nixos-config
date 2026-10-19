#!/usr/bin/env bash
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
rm -f /tmp/presented.ppm
PLAYER_DUMP_SWAPCHAIN=/tmp/presented.ppm "$here/launch-live.sh" --size=1200x800 --shot-after=200 > /dev/null 2>&1
