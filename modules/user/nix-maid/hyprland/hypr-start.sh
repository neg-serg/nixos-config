set -euo pipefail
LOG="/tmp/hypr-start.log"

# $1 = --login — called from files/gui/hypr/hyprland.lua the moment the login layer
# accepted the password. Anything else (or nothing) means "fresh": the compositor
# was started inside a live session (after a crash, by hand, or through the
# M4+SHIFT+F12 rescue bind) and the session units still hold the dead compositor's
# environment.
#
# --login tears nothing down. The session target has never been started in this
# user manager; the session units that must already be up (wl-daemon — the
# wallpaper behind the login screen — started deliberately in the login phase)
# are running; the ones that must not run yet (quickshell the bar, hypridle) were
# held back by the login-phase marker. Tearing the target down anyway is exactly
# what made the login feel slow: the stop/start below killed and restarted the
# session shell right after the password (PartOf=hyprland-session.target) together
# with the portals, and the socket wait added a second on top. 2026-09-19:
# password accepted 18:25:51, target reached only at 18:26:03.
mode="${1:-fresh}"
if [ "$mode" != "--login" ]; then
  mode=fresh
fi

log() {
  printf '%s %s\n' "$(date '+%H:%M:%S.%3N')" "$*" >> "$LOG"
}

: > "$LOG"
log "hypr-start $mode: begin"

# The compositor's environment has to be visible to the units started below: the
# user manager predates the compositor, so WAYLAND_DISPLAY and
# HYPRLAND_INSTANCE_SIGNATURE exist only in this process tree.
log "importing environment"
dbus-update-activation-environment --systemd --all
systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE QT_XDG_DESKTOP_PORTAL

# The desktop may start now: drop the systemd-visible login-phase marker (see
# modules/user/session/greetd/session-wrapper.sh). Without this, quickshell.service
# and hypridle.service stay skipped (ConditionPathExists=!…) and the session would
# come up without a bar. login.qml removes it as it writes "session"; this copy
# covers the rescue bind and a hand-flipped marker — both modes, because reaching
# this script at all means the session is allowed to start.
rm -f "${QS_LOGIN_STATE_DIR:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quickshell-login}/login-phase"

if [ "$mode" = "--login" ]; then
  log "login mode: keeping the running session units"

else
  # Let the compositor publish its sockets before the units bind to them.
  log "waiting for compositor sockets"
  sleep 1

  # Portals and the session target from the previous compositor: they hold the old
  # WAYLAND_DISPLAY, so stop them and let the target below start them again.
  log "cleaning stale session state"
  systemctl --user stop xdg-desktop-portal-hyprland.service xdg-desktop-portal-gtk.service hyprland-session.target || true
fi

# Stale failed state from the login phase (xdg-desktop-portal.service fails its
# start while no graphical session is active) must not be inherited: without this
# the target restarts a unit that is still marked failed.
log "resetting failed units"
systemctl --user reset-failed || true

log "starting hyprland-session.target"
systemctl --user start hyprland-session.target
log "hyprland-session.target: $(systemctl --user is-active hyprland-session.target)"
