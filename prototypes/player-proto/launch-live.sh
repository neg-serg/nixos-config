#!/usr/bin/env bash
# Start the player in the real session, sized like the design target.
set -u
here=$(cd "$(dirname "$0")" && pwd)
[ -s "$here/.libs" ] || "$here/libs.sh" > "$here/.libs"
exec env -u LD_LIBRARY_PATH LD_LIBRARY_PATH="$(cat "$here/.libs")" \
  "$here/target/release/player" --size=1440x900 > /tmp/live-app.log 2>&1
