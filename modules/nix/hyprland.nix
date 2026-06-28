{ config, inputs, lib, ... }:
{
  # Route Hyprland and its portal to the flake-pinned versions
  # Gated behind features.gui.enable to avoid pkgs.hyprland evaluation on headless hosts
  config = lib.mkIf config.features.gui.enable {
    nixpkgs.overlays = [
      inputs.hyprland.overlays.default # Hyprland wayland compositor
      inputs.xdg-desktop-portal-hyprland.overlays.default # XDG portal backend for Hyprland
      (_: prev: let inherit (prev.stdenv.hostPlatform) system; in {
        hyprlandPlugins = prev.hyprlandPlugins // {};
      })
    ];
  };
}
