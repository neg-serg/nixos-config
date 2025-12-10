{
  lib,
  config,
  ...
}:
with lib;
  mkIf config.features.gui.enable {
    home.sessionVariables = {
      # Wayland-first backends with sensible fallbacks
      GDK_BACKEND = "wayland";
      QT_QPA_PLATFORM = "wayland;xcb";
      SDL_VIDEODRIVER = "wayland,x11";
      CLUTTER_BACKEND = "wayland";
      XDG_CURRENT_DESKTOP = "Hyprland";
      XDG_SESSION_DESKTOP = "Hyprland";
      XDG_SESSION_TYPE = "wayland";

      # Toolkit-specific hints
      MOZ_ENABLE_WAYLAND = "1";
      ELECTRON_OZONE_PLATFORM_HINT = "auto";
    };
  }
