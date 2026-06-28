{
  lib,
  pkgs,
  ...
}:
{
  hyprlandConf = ''
    source = ~/.config/hypr/hyprland.lua
    source = ~/.config/hypr/animations/selected.conf
    source = ~/.config/hypr/xdph.conf
    source = ~/.config/hypr/permissions.conf
    source = ~/.config/hypr/local.d/*.conf
  '';

  permissionsConf = ''
    ecosystem {
        enforce_permissions = 1
    }
    permission = ${lib.getExe pkgs.grim}, screencopy, allow
    permission = ${lib.getExe pkgs.hyprlock}, screencopy, allow
  '';
}
