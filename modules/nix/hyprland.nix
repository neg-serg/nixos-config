{inputs, ...}: {
  # Route Hyprland, its portal, and the hy3 plugin in nixpkgs to the flake-pinned versions
  nixpkgs.overlays = [
    (_: prev: let
      inherit (prev.stdenv.hostPlatform) system;
    in {
      inherit (inputs.hyprland.packages.${system}) hyprland;
      inherit (inputs.xdg-desktop-portal-hyprland.packages.${system}) xdg-desktop-portal-hyprland;
      hyprlandPlugins =
        prev.hyprlandPlugins
        // {
          hy3 = inputs.hy3.packages.${system}.hy3;
        };
    })
  ];
}
