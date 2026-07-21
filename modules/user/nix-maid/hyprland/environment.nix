{ pkgs, ... }: {
  hyprlandConf = ''
    plugin = ${pkgs.hyprglass}/lib/hyprglass.so

    source = ~/.config/hypr/hyprland.lua
    source = ~/.config/hypr/animations/selected.conf
    source = ~/.config/hypr/local.d/*.conf
  '';
}
