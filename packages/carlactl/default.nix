##
# Package: carlactl
# Purpose: Console controller for routing external VSTs (Vital, ...) through
#   headless Carla. Generates .carxp projects via Carla's C API and runs
#   `pw-jack carla -n` so no GUI is needed; fzf for interactive picks.
#   The whole CLI runs under pw-jack: Carla is JACK-only and this host has no
#   jackd — PipeWire's libjack (LD_LIBRARY_PATH) is what makes engine_init work.
{
  python3,
  carla,
  pipewire,
  writeShellScriptBin,
}:
writeShellScriptBin "carlactl" ''
  export CARLA_SHARE_DIR=${carla}/share/carla
  export CARLA_LIB_DIR=${carla}/lib/carla
  export LD_LIBRARY_PATH=/run/current-system/sw/lib
  exec ${pipewire.jack}/bin/pw-jack ${python3}/bin/python3 ${./carlactl.py} "$@"
''
