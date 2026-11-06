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
# The legacy QML tree (files/quickshell) was deleted on 2026-11-02; git history is the rollback.
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
# the compiled worker is carried in the store here. /run/wrappers/bin first: it holds
# the setuid wrappers (unix_chkpwd, which the PAM password check reaches through
# the system profile) — see the note in greetd/session-wrapper.sh.
PATH="/run/wrappers/bin:$KBD/bin:/run/current-system/sw/bin:${PATH:-}"
export PATH

STATE_DIR="${PLEAMAR_LOGIN_STATE_DIR:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/pleamar-login}"
mkdir -p "$STATE_DIR" 2> /dev/null || true

LOG=/tmp/pleamar-login-layer.log

# The palette. A scene's `import "../../theme.plm"` is resolved beside the path the file was
# reached by, and the generated palette lives in ~/.config/pleamar/theme.plm (rewritten by
# pleamar-theme from the current wallpaper). Reached through the checkout, the lock would read the
# checkout's committed fallback instead, and the login would wear the default accent while the
# session wears the wallpaper's. An import root of symlinks in the login's own state directory is
# that path: the scenes stay live-linked to the tree, the palette is the generated one.
#
# The generated palette is checked with the scene first, and the tree's own is used when it does
# not compile. The theme unit cannot run during the login phase, and a malformed palette must cost
# the wallpaper's accent, not the login screen: nothing here is worth a lock face that cannot open.
root="$STATE_DIR/tree"
mkdir -p "$root" 2> /dev/null || true
ln -sfn "$TREE/shells" "$root/shells"
ln -sfn "$TREE/lib" "$root/lib"
ln -sfn "$TREE/theme.plm" "$root/theme.plm"
scene="$root/shells/lock/lock.plm"
theme="${XDG_CONFIG_HOME:-$HOME/.config}/pleamar/theme.plm"
if [ -r "$theme" ]; then
  ln -sfn "$theme" "$root/theme.plm"
  if "$PLEAMAR" --check "$scene" > /dev/null 2>&1; then
    printf 'login layer: palette "%s"\n' "$theme" >> "$LOG"
  else
    ln -sfn "$TREE/theme.plm" "$root/theme.plm"
    printf 'login layer: palette "%s" does not compile with the lock scene; the fallback is used\n' \
      "$theme" >> "$LOG"
  fi
fi

# The wallpaper behind the login screen. The daemon has to be painting before the
# lock is released, or the desktop appears on the compositor's own background for
# the ~2 s a cold Vulkan start takes. It cannot be started from hyprland.lua's
# login branch: an exec dispatched while the compositor parses its config reaches
# the user manager before WAYLAND_DISPLAY is in it, so the unit dies with "Could
# not find wayland compositor" and is only restarted by the session target after
# the password (2026-11-04 00:38:11-21 — the desktop came up without its
# wallpaper). This script runs with the compositor's own environment (the scene
# below connects with it), so the import and the start are done here, while the
# login screen still covers the desktop.
if command -v systemctl > /dev/null 2>&1 && command -v wl > /dev/null 2>&1; then
  systemctl --user import-environment WAYLAND_DISPLAY XDG_RUNTIME_DIR > /dev/null 2>&1 || true
  if ! wl query > /dev/null 2>&1; then
    # `reset-failed` first: the early start left the unit failed, and a failed
    # unit is not picked up by a plain `start` in the same transaction.
    # `--no-block`: the unit's ExecStartPost (`wl-restore-retry`) waits for the
    # daemon and restores the picture, and that must not hold the login screen
    # back — the lock is not even drawn yet.
    systemctl --user reset-failed wl-daemon.service > /dev/null 2>&1 || true
    systemctl --user restart --no-block wl-daemon.service > /dev/null 2>&1 || true
  fi
  printf 'login layer: wl-daemon "%s"\n' "$(systemctl --user is-active wl-daemon.service 2> /dev/null || true)" >> "$LOG"
fi

# The picture behind the card. The lock reads `wallpaper.path` — one absolute
# path — from its own data folder ($XDG_DATA_HOME/pleamar/lock, the integration
# slot of INTERFACES.md §1.2) and draws the shader's dot grid when there is none.
# Sources, freshest first: the path the theme pipeline watches, then wl-daemon's
# state — the image the daemon started above paints behind the lock surface, so
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

# The lock face is engaged once and keeps the box the scene had at that moment
# (`pleamar-lock-engage.patch`: a later request finds `engaged` and answers true),
# while the scene goes on drawing with whatever monitor it is given. A scene
# started before this compositor has settled its outputs —the 4K panel comes up
# in a fallback mode and the `hl.monitor` rule switches it afterwards— therefore
# freezes a face sized for a monitor that is not the one on screen: the login
# card lands in one quarter of the panel, three quarters stay empty, and the face
# is never re-made (cold boot 2026-11-02 00:11; a logout, where the mode is
# already right, was fine).
#
# So the scene waits for the outputs to be up and to stop changing. The list is
# read whole and compared with the previous sample, so any mode, scale or
# refresh-rate change restarts the wait; three equal samples in a row (300 ms of
# quiet) are what counts as settled, because a single repeat still fits inside a
# mode switch. Bounded at 5 s: a compositor that never answers, or a panel that
# never settles, must not keep the login screen away — a card in the wrong corner
# is bad, a black screen with no way to type is worse.
describe_outputs() {
  hyprctl monitors -j 2> /dev/null \
    | "$JQ" -r '[.[] | "\(.name) \(.width)x\(.height)@\(.refreshRate) scale \(.scale)"] | sort | join(",")' 2> /dev/null
}
#
# No `hyprctl` and no `jq` — another compositor, or a session started by hand —
# means nothing to read, so nothing to wait for: the scene starts at once, exactly
# as it did before this gate existed.
if command -v hyprctl > /dev/null 2>&1 && [ -x "$JQ" ]; then
  quiet=0
  samples=0
  now=""
  last=""
  while [ "$samples" -lt 50 ]; do
    now="$(describe_outputs)"
    if [ -n "$now" ] && [ "$now" = "$last" ]; then
      quiet=$((quiet + 1))
      [ "$quiet" -ge 3 ] && break
    else
      quiet=1
    fi
    last="$now"
    samples=$((samples + 1))
    sleep 0.1
  done
  printf 'login layer: outputs "%s" after %d ms\n' "${now:-none}" "$((samples * 100))" >> "$LOG"
else
  printf 'login layer: no hyprctl/jq here; the scene starts without waiting for the outputs\n' >> "$LOG"
fi

# Appended, not truncated: a cold boot's own log used to be wiped by the next
# attempt and by hyprland.lua's note, which is why the failure above left no
# trace. The scene's own lines carry on after this header.
started_at="$(wc -l < "$LOG" 2> /dev/null || echo 0)"
"$PLEAMAR" --scene "$scene" --no-hud --stall 0 >> "$LOG" 2>&1 &
scene_pid=$!

alive() { kill -0 "$scene_pid" 2> /dev/null; }

# ---- what the login costs on CPU (and who else is spending it) ----------------
#
# The frame log above answers "how fast", not "how much", and no other instrument can answer
# it for this phase: the lock scene is not a unit, so neither `systemctl show` nor the
# `pleamar-login-cpu` record (it reads the session's scenes a minute after the password) ever
# sees it. A login after a cold boot is also the one moment the machine is busy for another
# reason — podman, adguard, koito, the nix daemon and the rest of the boot start beside this
# screen — so a sample that named only the scene could not tell the greeter from its
# neighbours. Each line therefore carries the scene, the whole machine and the three busiest
# processes, and every login names its uptime: a boot login is the one with a small number
# there, a logout login has minutes or hours.
#
# One /proc read and one ps every five seconds, capped at two minutes, and the loop leaves as
# soon as the scene is gone. Nothing here is on the handover path: a sampler that cannot run
# costs the log a line, not the login.
printf 'login layer: login at %s s of uptime (boot %s)\n' \
  "$(awk '{ printf "%.0f", $1 }' /proc/uptime 2> /dev/null || echo unknown)" \
  "$(cat /proc/sys/kernel/random/boot_id 2> /dev/null || echo unknown)" >> "$LOG"

(
  # Busy and total jiffies of the whole machine, then the scene's own four fields: utime,
  # stime and the children it has waited for. A scene's workers are its children, so one
  # number is the whole scene.
  cpu_counters() {
    awk '/^cpu /{ idle=$5+$6; total=0; for (i=2;i<=NF;i++) total+=$i; printf "%.0f %.0f", total-idle, total }' /proc/stat
  }
  scene_jiffies() {
    awk '{ printf "%.0f", $14+$15+$16+$17 }' "/proc/$scene_pid/stat" 2> /dev/null || echo 0
  }
  # % of ONE core: the scene's delta divided by what one CPU spent in that interval (the
  # machine's total over all of them). `ps` gives a lifetime average, which is the useful
  # figure at boot: a job started ten seconds ago that has been busy since reads high.
  ncpu="$(nproc 2> /dev/null || echo 1)"
  read -r busy0 total0 <<< "$(cpu_counters)"
  scene0="$(scene_jiffies)"
  t=0
  while [ "$t" -lt 120 ]; do
    sleep 5
    t=$((t + 5))
    kill -0 "$scene_pid" 2> /dev/null || exit 0
    read -r busy1 total1 <<< "$(cpu_counters)"
    scene1="$(scene_jiffies)"
    top="$(ps -eo pcpu=,comm= --sort=-pcpu 2> /dev/null | head -3 \
      | awk '{ printf "%s %.1f%%%s", $2, $1, (NR < 3 ? ", " : "") }')"
    awk -v t="$t" -v s0="$scene0" -v s1="$scene1" -v b0="$busy0" -v b1="$busy1" \
      -v t0="$total0" -v t1="$total1" -v n="$ncpu" -v top="$top" 'BEGIN{
        d=t1-t0; per=(d>0 ? d/n : 0);
        printf "cpu · t=%ds · scene %.2f%% of a core · system %.0f%% · top: %s\n",
               t, (per>0 ? (s1-s0)/per*100 : 0), (d>0 ? (b1-b0)/d*100 : 0), top }' >> "$LOG"
    busy0=$busy1
    total0=$total1
    scene0=$scene1
  done
) > /dev/null 2>&1 &

# ---- what was actually drawn (best effort, never fatal) ----------------------
#
# A lock face draws the scene's box CENTRED on its monitor — the runtime's
# `configure` sets `view_origin = origin - (face - box) / 2` — so a box that is not
# the monitor's logical size shifts the whole login screen by half the difference.
# `size: full` did exactly that: the compiler writes `full` as a zero box, a zero box
# is centred on the monitor, and the scene's origin landed at the monitor's CENTRE —
# the clock and the card painted half a panel away, off the screen, with nothing in
# any log saying so. `pleamar-lock-full.patch` makes a `full` box stand for the
# face's own size and has the face print the three numbers below.
#
# This is the observational half and it only *reports*: killing a scene that may
# already hold the lock is a lockout, not a fix (ext-session-lock keeps the session
# locked when its client goes: pleamar --docs reference, the lock-screen section).
# A login screen with a shifted face is still usable, and nothing here can block it.
#
# What it reads, once per configured face (the engine's own line):
#   lock   · DP-2: box 1920x1080, face 1920x1080, from 0,10000
# `from` is where the scene's own plane starts for this face, and a named surface
# (the lock's `surface screen_lock`) is placed on a piece of that plane 10000 px
# below the one before it — the compiler does that so two surfaces never overlap,
# and the renderer draws the face from the same corner, so (0, 10000) is the
# normal reading, not a shift. What must equal the face is the BOX: a box smaller
# than the face is the centring difference that moved the login off screen before
# `pleamar-lock-full.patch`.
painted() {
  tail -n "+$((started_at + 1))" "$LOG" 2> /dev/null \
    | sed -n 's/^lock [^:]*: box \([0-9][0-9]*x[0-9][0-9]*\), face \([0-9][0-9]*x[0-9][0-9]*\), from \(.*\)$/\1 \2 \3/p' \
    | tail -1
}

# The compositor holds the session only once every face is up; that is the fact the
# scene's own handover rests on, so it is worth one line in the log. Bounded at 3 s
# and silent about failure: a compositor that does not answer is not an error here.
held=""
polls=0
while [ "$polls" -lt 30 ]; do
  held="$("$PLEAMAR" --say lock "get lock.held" 2> /dev/null)"
  case "$held" in 1 | true) break ;; esac
  alive || break
  polls=$((polls + 1))
  sleep 0.1
done

# One line with the three numbers, when the scene got as far as configuring a face:
# the next cold boot then answers "was the face the monitor's size at engage time,
# and did the scene paint from its corner" without a rebuild and without a second
# logout.
face="$(painted)"
box=""
face_size=""
from=""
if [ -n "$face" ]; then
  box="${face%% *}"
  rest="${face#* }"
  face_size="${rest%% *}"
  from="${rest#* }"
fi
# The same face in the pixels the panel has. A HiDPI panel gives one monitor two
# numbers that both read as "the screen" (here a 1920x1080 logical face painting
# 3840x2160 device buffers), and a log that names only one of them is how the shifted
# face above stayed unread for a day. Best effort: a compositor that does not answer
# leaves the field "unknown".
device=""
if size_json="$(hyprctl monitors -j 2> /dev/null)"; then
  device="$(printf '%s' "$size_json" \
    | "$JQ" -r '[.[] | select(.focused)][0] // .[0] | "\(.width)x\(.height) at scale \(.scale)"' 2> /dev/null || true)"
fi
printf 'login layer: lock.held "%s" after %d ms; compositor "%s"; box "%s"; face "%s" logical; device "%s"; from "%s"\n' \
  "${held:-none}" "$((polls * 100))" "${HYPRLAND_INSTANCE_SIGNATURE:+hyprland}" \
  "${box:-none}" "${face_size:-none}" "${device:-unknown}" "${from:-none}" >> "$LOG"
if [ -n "$from" ] && [ "$box" != "$face_size" ]; then
  printf 'login layer: WARNING the login face paints a "%s" box on a "%s" logical face (from "%s", "%s" device): the screen is shifted by half the difference; NOT restarted on purpose, a locker killed while it holds the lock leaves the session locked with nothing to type into\n' \
    "$box" "$face_size" "$from" "${device:-unknown}" >> "$LOG"
fi

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
