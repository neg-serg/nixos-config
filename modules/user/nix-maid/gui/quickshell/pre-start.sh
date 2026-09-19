qs_dir="$HOME/.config/quickshell"
src="@quickshellSrc@"

# Self-heal nix-maid symlinks: during `nixos-rebuild switch` the cleanup
# service deletes the static dir while quickshell can restart before
# maid-activation recreates it. If shell.qml is gone, deploy it by
# running the activation script directly.
#
# Do NOT `systemctl --user start --wait maid-activation.service` here:
# quickshell.service Wants= that unit, so the nested start job is queued
# behind the running quickshell start transaction and deadlocks until the
# 25s timeout on every first boot after a generation switch (observed
# ~+28s of panel-less startup). The direct activation below is the same
# script the unit would run and completes in ~3s.
if [ ! -e "$qs_dir/shell.qml" ] && [ -d "$qs_dir" ]; then
  # Run the SAME activation the unit would run (parsed from the unit
  # script). NOT `ls -t /nix/store/*-all-maid/...`: every store path
  # carries the epoch mtime, so ls -t picks a random generation and
  # can roll ~/.local/bin back to an old one (e.g. dropping the
  # glm-* scripts, breaking the Genelec wheel).
  unit_script=$(systemctl --user show maid-activation.service -p ExecStart --value 2> /dev/null | sed -n 's/.*path=\([^ ;]*\).*/\1/p')
  # The unit script resolves the correct activation path itself
  # (including $USER); run it directly.
  [ -n "$unit_script" ] && [ -x "$unit_script" ] && "$unit_script"
fi

# Theme/ — copy-once from Nix store, make writable
if [ ! -d "$qs_dir/Theme" ]; then
  mkdir -p "$qs_dir/Theme"
  cp -rT "$src/Theme" "$qs_dir/Theme" 2> /dev/null || true
  chmod -R u+w "$qs_dir/Theme" 2> /dev/null || true
fi

# Settings/ — force-copy on every start so repo changes (Theme.qml, Settings.qml)
# propagate; dir stays writable for qs runtime state.
mkdir -p "$qs_dir/Settings"
cp -rfT "$src/Settings" "$qs_dir/Settings" 2> /dev/null || true
chmod -R u+w "$qs_dir/Settings" 2> /dev/null || true

# Settings.json — copy-once, user-editable
if [ ! -f "$qs_dir/Settings.json" ]; then
  cp "$src/Settings.json" "$qs_dir/Settings.json" 2> /dev/null || true
  chmod u+w "$qs_dir/Settings.json" 2> /dev/null || true
fi

# Components/ — force-copy on every start for dev iteration
mkdir -p "$qs_dir/Components"
cp -rfT "$src/Components" "$qs_dir/Components" 2> /dev/null || true
chmod -R u+w "$qs_dir/Components" 2> /dev/null || true

# Bar/ — force-copy on every start for dev iteration
mkdir -p "$qs_dir/Bar"
cp -rfT "$src/Bar" "$qs_dir/Bar" 2> /dev/null || true
chmod -R u+w "$qs_dir/Bar" 2> /dev/null || true

# Helpers/ — force-copy on every start for dev iteration
mkdir -p "$qs_dir/Helpers"
cp -rfT "$src/Helpers" "$qs_dir/Helpers" 2> /dev/null || true
chmod -R u+w "$qs_dir/Helpers" 2> /dev/null || true

# Notifications/ — force-copy on every start for dev iteration
mkdir -p "$qs_dir/Notifications"
cp -rfT "$src/Notifications" "$qs_dir/Notifications" 2> /dev/null || true
chmod -R u+w "$qs_dir/Notifications" 2> /dev/null || true

# Widgets/ — force-copy on every start. The nix-maid static tree exposes it
# as a symlink without a qmldir, and Quickshell cannot load files from that
# symlink ("File not found"/"No such file or directory" for
# MusicPopup.qml/ScreenshotToast.qml). Copying to a real dir fixes loading.
# Remove the stale nix-maid symlink first so the copy lands in a real dir.
rm -rf "$qs_dir/Widgets"
mkdir -p "$qs_dir/Widgets"
cp -rfT "$src/Widgets" "$qs_dir/Widgets" 2> /dev/null || true
cp -rT "$src/Widgets" "$qs_dir/Widgets" 2> /dev/null || true
chmod -R u+w "$qs_dir/Widgets" 2> /dev/null || true

# art/, shaders/ — force-copy on every start: the static symlink tree is
# created by nix-maid activation AFTER the switch, so a shell started
# meanwhile reads a half-deployed tree (missing 8.svg, wedge_clip.qsb →
# startup warnings). Deterministic deployment, same pattern as above.
mkdir -p "$qs_dir/art"
cp -rfT "$src/art" "$qs_dir/art" 2> /dev/null || true
chmod -R u+w "$qs_dir/art" 2> /dev/null || true

mkdir -p "$qs_dir/shaders"
cp -rfT "$src/shaders" "$qs_dir/shaders" 2> /dev/null || true
chmod -R u+w "$qs_dir/shaders" 2> /dev/null || true

# ── Genelec volume: seed the runtime state file before the panel starts ──────
# The widget reads $XDG_RUNTIME_DIR/genlc-volume at startup and *sends* whatever
# it finds (the MIDI anchor pushes the widget's volume to the monitors as soon as
# the adapter is up), and the file is wiped with the runtime dir on every logout.
# Left empty, the widget fell back to its hardcoded -40 dB default and pushed the
# monitors there on each restart — the "volume drops to -40 after a restart"
# report. The last value the widget committed lives in its own cache, so copy it
# in before quickshell reads the file; the widget's own restore in
# Services/Genelec.qml stays as the fallback for a panel restart inside a
# session.
genlc_state="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/genlc-volume"
if [ ! -s "$genlc_state" ] && command -v jq > /dev/null 2>&1; then
  v="$(jq -r '.genelecVolume // empty' "${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/state.json" 2> /dev/null || true)"
  case "$v" in
    -[0-9]*) printf '%s' "$v" > "$genlc_state" 2> /dev/null || true ;;
  esac
fi
