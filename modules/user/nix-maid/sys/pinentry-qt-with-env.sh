# shellcheck disable=SC2012,SC2155
if [ -z "$WAYLAND_DISPLAY" ] && [ -n "$XDG_RUNTIME_DIR" ]; then
  wayland_socket=""
  wayland_socket=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'wayland-*' -print -quit 2> /dev/null || true)
  if [ -n "$wayland_socket" ]; then
    wayland_base=$(basename "$wayland_socket")
    export WAYLAND_DISPLAY="$wayland_base"
  fi
fi
if [ -z "$DISPLAY" ] && [ -n "$WAYLAND_DISPLAY" ]; then
  export DISPLAY=:0
fi
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ] && [ -n "$XDG_RUNTIME_DIR" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
fi

# Ensure coreutils are in path
PATH="$PATH:@COREUTILS@/bin" # GNU Core Utilities

"@PINENTRY@" "$@" # Qt-native pinentry (Wayland-compatible)
