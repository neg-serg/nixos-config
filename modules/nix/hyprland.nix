{ inputs, ... }: {
  # Route Hyprland and its portal in nixpkgs to the flake-pinned versions
  nixpkgs.overlays = [
    (_: prev: let
      system = prev.stdenv.hostPlatform.system;
    in {
      hyprland = inputs.hyprland.packages.${system}.hyprland;
      xdg-desktop-portal-hyprland =
        inputs.xdg-desktop-portal-hyprland.packages.${system}.xdg-desktop-portal-hyprland;
    })
  ];
}

