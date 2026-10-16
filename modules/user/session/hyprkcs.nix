##
# Module: user/session/hyprkcs
# Purpose: hyprKCS — GTK4 keybind manager / cheat sheet for Hyprland, toggled
#   as a layer-shell overlay from SUPER+SHIFT+slash (files/gui/hypr/hyprland.lua).
# Feature flag: features.gui.hyprKCS.enable (declared in features/gui.nix)
# Caveat: upstream parses hyprlang configs only, so with the Lua config the
#   overlay lists nothing until kosa12/hyprKCS#77 lands — the package stays
#   installed for that, and the overlay itself launches fine.
{
  lib,
  config,
  pkgs,
  ...
}:
lib.mkIf (config.lib.neg.enabled "gui" && config.features.gui.hyprKCS.enable) {
  environment.systemPackages = [
    pkgs.hyprkcs # Hyprland keybind manager / cheat sheet (GTK4 layer-shell overlay)
  ];
}
