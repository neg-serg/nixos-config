{ pkgs, ... }: {
  hyprlandConf = ''
    plugin = ${pkgs.hyprglass}/lib/hyprglass.so
    plugin = ${pkgs.hyprlandPlugins.hy3}/lib/libhy3.so
    plugin = ${pkgs.hyprlandPlugins.hyprspace}/lib/libhyprspace.so

    # Lua-only config: legacy hyprlang .conf files are NOT sourced here
    # (animations/selected.conf is a hyprlang duplicate — animations live in
    # hyprland.lua via hl.animation; only .lua files are allowed below).
    source = ~/.config/hypr/hyprland.lua
    source = ~/.config/hypr/local.d/*.lua
  '';
}
