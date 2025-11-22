{
  lib,
  ...
}: {
  # Ensure xdg-desktop-portal-hyprland is not skipped due to ConditionEnvironment.
  # Hyprland already imports WAYLAND_DISPLAY into the systemd user manager.
  systemd.user.services.xdg-desktop-portal-hyprland.Unit.ConditionEnvironment = lib.mkForce "";
}

