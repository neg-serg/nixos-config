{
  lib,
  pkgs,
  ...
}:
{
  hyprlandConf = _hy3Enabled: ''
    env = GDK_SCALE,2
    env = QT_AUTO_SCREEN_SCALE_FACTOR,1
    env = QT_ENABLE_HIGHDPI_SCALING,1
    env = XCURSOR_SIZE,23
    env = GDK_BACKEND,wayland
    env = QT_QPA_PLATFORM,wayland;xcb
    env = SDL_VIDEODRIVER,wayland,x11
    env = CLUTTER_BACKEND,wayland
    env = XDG_CURRENT_DESKTOP,Hyprland
    env = XDG_SESSION_DESKTOP,Hyprland
    env = XDG_SESSION_TYPE,wayland
    env = MOZ_ENABLE_WAYLAND,1
    env = ELECTRON_OZONE_PLATFORM_HINT,auto
    env = GTK_USE_PORTAL,1
    env = QT_QPA_PLATFORMTHEME,xdgdesktopportal

    exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE QT_XDG_DESKTOP_PORTAL
    exec-once = systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE QT_XDG_DESKTOP_PORTAL

    source = ~/.config/hypr/init.conf
    source = ~/.config/hypr/permissions.conf

    source = ~/.config/hypr/local.d/*.conf
  '';

  permissionsConf = _hy3Enabled: ''
    ecosystem {
        enforce_permissions = 1
    }
    permission = ${lib.getExe pkgs.grim}, screencopy, allow
    permission = ${lib.getExe pkgs.hyprlock}, screencopy, allow
  '';
}
