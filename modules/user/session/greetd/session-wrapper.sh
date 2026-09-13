#!/bin/sh
# Give the previous compositor time to release DRM master after greetd
# transitions from the greeter session to the user session.
# Atomic KMS is required for HDR metadata (hdr_output_metadata only works
# through atomic commits; the legacy interface has no HDR support).
# If atomic KMS misbehaves on RDNA4, investigate before re-enabling
# AQ_NO_ATOMIC — it silently disables HDR.
# export AQ_NO_ATOMIC=1
# Session chosen in the greeter arrives as args (Exec= from
# /usr/share/wayland-sessions/*.desktop). No args = Hyprland (default).
# Hyprland always routes through start-hyprland (env + session target).
# /run/wrappers/bin MUST stay first: it holds the setuid sudo (and su,
# newuidmap, …) wrapper — prepending only sw/bin makes `sudo` resolve to
# the non-setuid store binary ("must be owned by uid 0 and have the
# setuid bit set").
export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$PATH"
if [ "$#" -eq 0 ]; then
  exec /run/current-system/sw/bin/start-hyprland > /tmp/hyprland-debug.log 2>&1
fi
case "$1" in
  *[Hh]yprland*) exec /run/current-system/sw/bin/start-hyprland > /tmp/hyprland-debug.log 2>&1 ;;
  *) exec "$@" > /tmp/wayland-session.log 2>&1 ;;
esac
