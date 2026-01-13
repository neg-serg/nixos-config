{ inputs, ... }:
{
  # Route Hyprland, its portal, and the hy3 plugin in nixpkgs to the flake-pinned versions
  nixpkgs.overlays = [
    inputs.hyprland.overlays.default # Hyprland wayland compositor overlay
    inputs.xdg-desktop-portal-hyprland.overlays.default # XDG portal implementation for Hyprland overlay
    (
      _: prev:
      let
        inherit (prev.stdenv.hostPlatform) system;
      in
      {
        hyprlandPlugins = prev.hyprlandPlugins // {
          # "borders-plus-plus" = inputs.hyprland-plugins.packages.${system}."borders-plus-plus";
          # dynamic-cursors removed
          hy3 = inputs.hy3.packages.${system}.hy3;
        };
      }
    )
  ];
}
