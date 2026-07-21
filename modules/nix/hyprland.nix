{
  config,
  inputs,
  lib,
  ...
}: {
  # Route Hyprland and its portal to the flake-pinned versions
  # Gated behind features.gui.enable to avoid pkgs.hyprland evaluation on headless hosts
  config = lib.mkIf config.features.gui.enable {
    nixpkgs.overlays = [
      inputs.hyprland.overlays.hyprland-packages
      inputs.xdg-desktop-portal-hyprland.overlays.default
    ];
  };
}
