{
  inputs,
  nixpkgs,
  ...
}:
let

  hyprlandOverlay =
    system:
    (_: prev: {
      inherit (inputs.xdg-desktop-portal-hyprland.packages.${system}) xdg-desktop-portal-hyprland;
      hyprlandPlugins = prev.hyprlandPlugins // {
        # "borders-plus-plus" = inputs.hyprland-plugins.packages.${system}."borders-plus-plus";
        # dynamic-cursors removed
        hy3 = inputs.hy3.packages.${system}.hy3;
      };
    });
  # Note: inputs.hyprland.overlays.default is applied separately in mkPkgs

  mkPkgs =
    system:
    import nixpkgs {
      inherit system;
      overlays = [
        ((import ../packages/overlay.nix) inputs)
        inputs.hyprland.overlays.default
        inputs.nyx.overlays.default
        (hyprlandOverlay system)
      ];
      config = import ./pkgs-config.nix;
    };

  mkCustomPkgs = pkgs: import ../packages/flake/custom-packages.nix { inherit pkgs; };
  mkIosevkaNeg = system: inputs."iosevka-neg".packages.${system};
in
{
  inherit mkPkgs mkCustomPkgs mkIosevkaNeg;
}
