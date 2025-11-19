{inputs, ...}: {
  # Route Hyprland and its portal in nixpkgs to the flake-pinned versions
  nixpkgs.overlays = [
    (_: prev: let
      inherit (prev.stdenv.hostPlatform) system;
    in {
      inherit (inputs.hyprland.packages.${system}) hyprland;
      inherit (inputs.xdg-desktop-portal-hyprland.packages.${system}) xdg-desktop-portal-hyprland;
    })
  ];
}
