# pleamar login layer — the login screen of the single-compositor session.
#
# Installed as `pleamar-login-layer` (modules/user/session/greetd.nix) and called
# from files/gui/hypr/hyprland.lua while the wrapper's marker says "login". The
# screen is the pleamar lock scene (files/pleamar/shells/lock/lock.plm): a
# `kind: lock` surface born locked, painted by the same compositor that will run
# the session, so no greeter process exits and no DRM mode is re-set on login.
#
# The password is checked by the scene's own logic (`sys.ask("auth.check", …)` in
# lock.luau) through the real PAM service `pleamar` — the same stack the legacy
# Quickshell login ran — and nothing here touches the password. On a right one the
# logic raises `fact unlocked`, the scene's rule turns that into `locked = false`
# and the ext-session-lock surface closes. This script then writes "session" into
# the wrapper's marker and returns, which is what makes hyprland.lua start the
# desktop.
#
# ## The handover contract this file relies on (pleamar 0.7.4, checked by hand)
#
# `pleamar --say` talks to the scene over $XDG_RUNTIME_DIR/pleamar/lock.sock. The
# exit status alone does not decide anything — a timeout exits 0 too — so the text
# of the answer is what this script reads:
#
#   pleamar --say lock "wait unlocked == true 55s"
#       "yes, after N ms"                 the password was accepted
#       "? not after 55 s: …"             still locked
#       "? the render does not answer"    the scene is gone
#   pleamar --say lock "get unlocked"     "true" / "false"
#   pleamar --say lock "get locked"       "true" / "false"  (the scene's wish)
#   pleamar --say lock "get lock.held"    "1" / "0"  (whether the *compositor*
#                                          really holds the session lock)
#   pleamar --say lock "fact locked false" / "quit"
#
# One `wait` call is capped at 62 s on the asking side, so the wait is repeated:
# only a right password or the scene dying leaves the loop. `--stall 0` and
# `--no-hud` are the flags the session units run their scenes with
# (modules/user/nix-maid/gui/pleamar.nix): `--stall` is pleamar's debug live-lock
# after every decision (600 ms by default) and the login screen has no reason to
# pay for it; `--no-hud` keeps the frame graph off the screen the lock owns.
#
# A wrong password stays inside the scene (its own retry window, `retryDelayMs`),
# so this script never sees it: it returns on a right password, on a scene that
# will not start, or on a scene that died. hyprland.lua retries the layer three
# times and then leaves the M4+SH+F12 escape hatch as the way in.
#
# PH3-L's PAM matrix (right password, wrong password, no enrolled finger, layout
# switch) is a human gate: it is run by the owner at the next logout, never by a
# test. Rolling back is a `git revert` of this wiring or the previous generation;
# files/quickshell stays in the tree until that gate has passed.
set -u

PLEAMAR="@pleamar@"
JQ="@jq@"
KBD="@kbdHelpers@"

# The tree the scene is loaded from. /etc/pleamar-lock is the deployed copy of
# files/pleamar (environment.etc in greetd.nix): during the login phase the session
# target has not started and nix-maid has not linked ~/.config/pleamar yet, so the
# scene has to come from the store and not from the home directory.
#
# The checkout wins while it exists, exactly as the Quickshell layer did: the
# scenes are live-linked into the session (~/.config/pleamar/shells ->
# /etc/nixos/files/pleamar/shells), so a scene edited in the repo is the one the
# desktop runs, and the login screen must not show a different one. The deployed
# copy stays the fallback for a system whose /etc/nixos is not this checkout.
# Either tree is a complete import root: lock.plm imports ../../lib/*.plm, which
# the compiler resolves beside the path the file was reached by.
TREE="@pleamarTree@"
if [ -f /etc/nixos/files/pleamar/shells/lock/lock.plm ]; then
  TREE=/etc/nixos/files/pleamar
fi
if [ ! -f "$TREE/shells/lock/lock.plm" ]; then
  echo "pleamar login layer: no lock scene in $TREE" >&2
  exit 1
fi

# The scene spawns its helpers by name: `cat` for /etc/hostname and
# `pleamar-kbdlayout` for the layout chip (permissions in lock.plm). ~/.local/bin,
# where nix-maid puts that worker for the session, does not exist yet at login, so
# the same script is carried in the store here. /run/wrappers/bin first: it holds
# the setuid wrappers (unix_chkpwd, which the PAM password check reaches through
# the system profile) — see the note in greetd/session-wrapper.sh.
PATH="/run/wrappers/bin:$KBD/bin:/run/current-system/sw/bin:${PATH:-}"
export PATH

STATE_DIR="${QS_LOGIN_STATE_DIR:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quickshell-login}"
mkdir -p "$STATE_DIR" 2> /dev/null || true

# The picture behind the card. The lock reads `wallpaper.path` — one absolute
# path — from its own data folder ($XDG_DATA_HOME/pleamar/lock, the integration
# slot of INTERFACES.md §1.2) and draws the shader's dot grid when there is none.
# Sources, freshest first: the path the theme pipeline watches, then wl-daemon's
# state — the image the compositor already paints behind the lock surface, so
# releasing the lock reveals the same picture. Nothing is published when neither
# names an existing file: a stale path is worse than the dot grid.
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/pleamar/lock"
mkdir -p "$data_dir" 2> /dev/null || true
wall="$(head -1 "$HOME/.cache/pleamar/wallpaper-path" 2> /dev/null || true)"
if [ -z "$wall" ] || [ ! -f "$wall" ]; then
  wall="$("$JQ" -r '.outputs | to_entries | .[0].value.wallpaper_path // empty' \
    "$HOME/.local/state/wl/state.json" 2> /dev/null || true)"
fi
if [ -n "$wall" ] && [ -f "$wall" ]; then
  printf '%s\n' "$wall" > "$data_dir/wallpaper.path" 2> /dev/null || true
fi

# Keyboard layout: under a session lock the compositor's own binds do not fire,
# and hyprland.lua sets kb_options = "" — no xkb group-switch key either. A login
# screen that happens to be in the wrong layout cannot be typed into at all: the
# password arrives as Cyrillic and PAM rejects it with nothing in the UI hinting
# why (2026-09-19 18:05, three failed attempts on a session whose focused window
# was Russian). Index 0 is `us`, the first entry of hyprland.lua's kb_layout; the
# scene's layout chip switches it from inside the lock surface afterwards.
hyprctl switchxkblayout all 0 > /dev/null 2>&1 || true

LOG=/tmp/pleamar-login-layer.log
"$PLEAMAR" --scene "$TREE/shells/lock/lock.plm" --no-hud --stall 0 > "$LOG" 2>&1 &
scene_pid=$!

alive() { kill -0 "$scene_pid" 2> /dev/null; }

while alive; do
  answer="$("$PLEAMAR" --say lock "wait unlocked == true 55s" 2>&1)"
  case "$answer" in
    "yes, after"*) break ;;
  esac
  # A timed-out wait returns at once; the scene may still be starting (its socket
  # appears with the first frame), so the retry is paced.
  sleep 0.2
done

if ! alive; then
  echo "pleamar login layer: the lock scene exited before the password was accepted" >&2
  exit 1
fi

# ------------------------------------------------------------------ handover
# 1. The marker first: hyprland.lua reads it the moment this script returns and
#    only then starts the desktop. Same file, same protocol and same path as the
#    Quickshell layer wrote (see greetd/session-wrapper.sh), renamed atomically.
printf 'session\n' > "$STATE_DIR/state.tmp" && mv -f "$STATE_DIR/state.tmp" "$STATE_DIR/state"

# 2. The login-phase marker. While it exists the session's scene units and
#    hypridle refuse to start (ConditionPathExists=!…/login-phase), so nothing of
#    the desktop comes up behind the lock face.
rm -f "$STATE_DIR/login-phase"

# 3. The lock surface. The scene's own rule has already released it (`on unlocked
#    { locked = false }`); saying it again is the documented, repeatable route.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ "$("$PLEAMAR" --say lock "get locked" 2> /dev/null)" = "false" ] && break
  "$PLEAMAR" --say lock "fact locked false" > /dev/null 2>&1
  sleep 0.1
done

# 4. Take the scene down, but never while the compositor still holds the lock:
#    ext-session-lock keeps the session locked when its client goes, and then
#    nothing on screen could unlock it. `lock.held` is the compositor's own word
#    on whether it does. If it never clears, the scene is left running — the
#    desktop then starts behind a lock face the owner can still type into, which
#    is recoverable; a black screen is not.
held=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  held="$("$PLEAMAR" --say lock "get lock.held" 2> /dev/null)"
  case "$held" in 0 | false) break ;; esac
  sleep 0.1
done
case "$held" in
  0 | false) "$PLEAMAR" --say lock quit > /dev/null 2>&1 ;;
  *) echo "pleamar login layer: the compositor still holds the lock ('$held'); leaving the scene up" >> "$LOG" ;;
esac

exit 0
