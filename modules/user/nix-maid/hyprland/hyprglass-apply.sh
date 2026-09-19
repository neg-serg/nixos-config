#!/usr/bin/env bash
# Push the hyprglass settings into the running session. The plugin only applies
# its config when it is handed over (session start), so a value that changed
# later — a switch, or a slider in the Glass panel — needs this to take effect
# without a re-login. The deployed base file is applied first, then the local
# overrides the panel writes.
set -euo pipefail
hyprctl_bin="@hyprctl@"

# Only load when it is not there yet: `plugin load` on a loaded plugin prints
# "Cannot load a plugin twice!" on every apply, which is noise in the journal.
if ! "$hyprctl_bin" plugin list 2>/dev/null | grep -qi hyprglass; then
  "$hyprctl_bin" plugin load @plugin@ || true
fi

# Let a burst of writes (a slider drag) settle so the last value is the one that
# lands, instead of pushing every intermediate step.
sleep 0.15

for f in "$HOME/.config/hypr/hyprglass.lua" "$HOME/.config/hypr/hyprglass-user.lua"; do
  [ -r "$f" ] || continue
  # hyprctl eval takes the code as one argument and reads a leading "--" (Lua
  # comment) as a flag, hence the leading newline.
  "$hyprctl_bin" eval "
$(cat "$f")" || true
done
