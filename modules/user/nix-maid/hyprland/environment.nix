{
  lib,
  pkgs,
  ...
}:
{
  hyprlandConf = ''
    source = ~/.config/hypr/hyprland.lua
    source = ~/.config/hypr/animations/selected.conf
    source = ~/.config/hypr/local.d/*.conf
  '';
}
