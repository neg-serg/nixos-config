set -euo pipefail
LOG="/tmp/hypr-start.log"
echo "Starting hypr-start at $(date)" > "$LOG"

# Wait a moment for Hyprland to fully initialize sockets
sleep 1

# Import environment
echo "Importing environment..." >> "$LOG"
dbus-update-activation-environment --systemd --all
systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE QT_XDG_DESKTOP_PORTAL

# Stop any stale portals or session targets to force clean state
echo "Cleaning stale session state..." >> "$LOG"
systemctl --user stop xdg-desktop-portal-hyprland.service xdg-desktop-portal-gtk.service hyprland-session.target || true
systemctl --user reset-failed

# Start session
echo "Starting hyprland-session.target..." >> "$LOG"
systemctl --user start hyprland-session.target
echo "Done." >> "$LOG"
