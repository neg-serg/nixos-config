# qs login layer — the login screen of the single-compositor session.
#
# Installed as `qs-login-layer` (modules/user/session/greetd.nix) and called from
# files/gui/hypr/hyprland.lua while the wrapper's marker says "login". It runs
# until the password is accepted: files/quickshell/greeter/login.qml writes
# "session" into the marker and quits, then hyprland.lua starts the desktop.
#
# /etc/quickshell is the deployed copy of files/quickshell (environment.etc in
# greetd.nix) — the login screen must not depend on the user's ~/.config/quickshell
# being in place: during the login phase the session target has not started and
# nix-maid has not deployed anything into the home directory yet.
#
# QML2_IMPORT_PATH is what makes the tree importable as the `qs` module, same as
# the old greeter's invocation; without it LockState/LockContent/BackgroundImage
# (import qs / qs.lock / qs.background) do not resolve.
set -u

export QML2_IMPORT_PATH="/etc/quickshell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"

# `quickshell` here is the wrapped package (modules/user/nix-maid/gui/quickshell.nix):
# it carries the Qt import paths, the icon theme and the extra PATH, so the login
# screen gets the same toolkit environment as the desktop shell.
exec quickshell -p /etc/quickshell/greeter/login.qml > /tmp/qs-login-layer.log 2>&1
