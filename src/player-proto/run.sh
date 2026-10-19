#!/usr/bin/env bash
# Run the prototype with the library paths a nix-wrapped Vulkan app gets for free
# (NixOS has no ld.so.cache: winit dlopens libwayland-client/libxkbcommon, ash dlopens
# libvulkan). The path list is cached in .libs — discovery walks the whole store and would
# otherwise cost 100+ ms *inside the measured process*.
#
# Measurement trap worth remembering: /proc/self/stat starttime is set at fork(), not at
# exec(), so any work this script does before `exec` is charged to the application's age.
# The discovery below therefore happens once, and measure.sh bypasses this script entirely.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
cache="$here/.libs"
if [ ! -s "$cache" ]; then "$here/libs.sh" > "$cache"; fi
exec env -u LD_LIBRARY_PATH LD_LIBRARY_PATH="$(cat "$cache")" \
  "${PROTO_BIN:-$here/target/release/player-proto}" "$@"
