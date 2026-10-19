#!/usr/bin/env bash
# Self-diagnosis in the real session: the app renders a frame offscreen and writes it as PPM,
# so a black window can be separated from a black render.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
rm -f /tmp/radv-self.ppm /tmp/diag.log
"$here/launch-live.sh" --size=1200x800 --shot=/tmp/radv-self.ppm --shot-after=60 >/tmp/diag-launcher.log 2>&1
echo "rc=$?" >> /tmp/diag.log
cp /tmp/live-app.log /tmp/diag.log 2>/dev/null || true
ls -l /tmp/radv-self.ppm >> /tmp/diag.log 2>&1
