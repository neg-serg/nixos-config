#!/bin/sh
# greetd default session — runs as the main user.
#
# Single-compositor login: greetd opens the PAM/logind session for the main user
# and this script starts the session compositor. No greeter session, no second
# compositor: the login screen is a quickshell session-lock layer inside this
# compositor (files/quickshell/greeter/login.qml), started by
# files/gui/hypr/hyprland.lua while the marker below reads "login".
#
# greetd starts the default session whenever no session is running — also after
# the user logs out, since the compositor *is* the default session (there is no
# session for greetd to fall back from) — so the login screen comes back without
# a separate greeter process.
#
# Marker: $QS_LOGIN_STATE_DIR/state
#   login   — no successful login in this session yet; show the login layer
#   session — login done; hyprland.lua starts the desktop session
#
# The directory lives inside XDG_RUNTIME_DIR (/run/user/$UID), which logind
# wipes when the session ends: logging out (or a compositor crash) removes the
# marker, so the next greetd session starts at the login screen again without
# anyone having to reset it. Linger is off for the main user — a lingering
# runtime dir would keep "session" and bring the desktop straight back up.
#
# The same directory is exported to the compositor and to the login layer, so all
# of them (including files/quickshell/scripts/login-wallpaper.sh) agree on one
# path: hyprland.lua reads the marker, login.qml writes it.
#
# Only the Hyprland session can be started now: the greeter's session list (and
# the X11/FVWM entries it offered) went away with the greeter — this compositor
# *is* the session, and its config is the session's own.
#
# Atomic KMS is required for HDR metadata (hdr_output_metadata only works through
# atomic commits; the legacy interface has no HDR support). If atomic KMS
# misbehaves on RDNA4, investigate before re-enabling AQ_NO_ATOMIC — it silently
# disables HDR; the compositor no longer has to hand DRM master over on login, so
# only that caveat is left of the old wrapper's comment.
# export AQ_NO_ATOMIC=1
#
# /run/wrappers/bin MUST stay first: it holds the setuid sudo (and su,
# newuidmap, …) wrapper — prepending only sw/bin makes `sudo` resolve to
# the non-setuid store binary ("must be owned by uid 0 and have the setuid
# bit set"). setuid and unix_chkpwd also live there; the login layer's PAM
# password check runs as a normal user and needs unix_chkpwd to read
# /etc/shadow.
set -u

export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$PATH"

: "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
export XDG_RUNTIME_DIR
export QS_LOGIN_STATE_DIR="$XDG_RUNTIME_DIR/quickshell-login"

# logind creates XDG_RUNTIME_DIR for the greetd session before this script runs;
# the mkdir is for a compositor started by hand (outside greetd).
mkdir -p "$QS_LOGIN_STATE_DIR" 2> /dev/null || true

# Wait for input devices before starting the compositor: without this the first
# seconds of the login screen would not take keyboard/mouse input.
while ! ls /dev/input/event* > /dev/null 2>&1; do
  sleep 0.2
done

# A fresh logind session means an empty runtime dir, i.e. a fresh login screen.
if [ ! -r "$QS_LOGIN_STATE_DIR/state" ]; then
  printf 'login\n' > "$QS_LOGIN_STATE_DIR/state"
fi

# Systemd-visible half of the same marker: quickshell.service and hypridle.service
# carry ConditionPathExists=!%t/quickshell-login/login-phase, i.e. they refuse to
# start while the login screen is up. They have to: nix-maid's sd-switch starts
# changed units *directly*, bypassing the session target, and did exactly that
# during the login phase (2026-09-19 18:25:47 — the bar came up behind the lock
# surface; hypr-start then killed and restarted it right after the password, which
# is both wasted work and a visible blink). login.qml removes the file when the
# password is accepted, and hypr-start removes it as well, so a crashed layer can
# never leave the desktop blocked.
: > "$QS_LOGIN_STATE_DIR/login-phase"

# Wallpaper for the login layer: resolved by the script the session side also
# asks (scripts/wl-wallpaper-resolve.sh), so login and desktop show one image.

if [ -x /etc/quickshell/scripts/login-wallpaper.sh ]; then
  /etc/quickshell/scripts/login-wallpaper.sh || true
fi

exec /run/current-system/sw/bin/start-hyprland > /tmp/hyprland-debug.log 2>&1
