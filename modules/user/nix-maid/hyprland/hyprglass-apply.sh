#!/usr/bin/env bash
# Push the hyprglass settings into the running session. The plugin only applies
# its config when it is handed over (session start), so a value that changed
# later — a switch, or a slider in the Glass panel — needs this to take effect
# without a re-login. The deployed base file is applied first, then the local
# overrides the panel writes.
set -euo pipefail
hyprctl_bin="@hyprctl@"

# Already loaded when the session-start hook ran; the failure is fine.
"$hyprctl_bin" plugin load @plugin@ || true

for f in "$HOME/.config/hypr/hyprglass.lua" "$HOME/.config/hypr/hyprglass-user.lua"; do
  [ -r "$f" ] || continue
  # hyprctl eval takes the code as one argument and reads a leading "--" (Lua
  # comment) as a flag, hence the leading newline.
  "$hyprctl_bin" eval "
$(cat "$f")" || true
done
