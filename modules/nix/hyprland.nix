{ config, inputs, lib, ... }:
{
  # Route Hyprland and its portal to the flake-pinned versions
  # Gated behind features.gui.enable to avoid pkgs.hyprland evaluation on headless hosts
  config = lib.mkIf config.features.gui.enable {
    nixpkgs.overlays = [
      inputs.hyprland.overlays.hyprland-packages # Hyprland with all deps (aquamarine, hyprlang, hyprcursor, guiutils, etc.)
      inputs.xdg-desktop-portal-hyprland.overlays.default # XDG portal backend for Hyprland
      (_: prev: {
        hyprlandPlugins = prev.hyprlandPlugins // {};
      })
    ];
  };
}
