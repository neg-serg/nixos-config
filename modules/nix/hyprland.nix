{ config, inputs, lib, ... }:
{
  # Route Hyprland, its portal, and the hy3 plugin in nixpkgs to the flake-pinned versions
  # Gated behind features.gui.enable to avoid pkgs.hyprland evaluation on headless hosts
  config = lib.mkIf config.features.gui.enable {
    nixpkgs.overlays = [
      inputs.hyprland.overlays.default # Hyprland wayland compositor
      inputs.xdg-desktop-portal-hyprland.overlays.default # XDG portal backend for Hyprland
      (_: prev: let inherit (prev.stdenv.hostPlatform) system; in {
        hyprlandPlugins = prev.hyprlandPlugins // {
          hy3 = inputs.hy3.packages.${system}.hy3; # tiling plugin for Hyprland
        };
      })
    ];
  };
}
