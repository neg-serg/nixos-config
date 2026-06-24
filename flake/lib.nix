{ inputs, nixpkgs, ... }:
let
  hyprlandOverlay = system: (_: prev: {
    inherit (inputs.xdg-desktop-portal-hyprland.packages.${system}) xdg-desktop-portal-hyprland;
    hyprlandPlugins = prev.hyprlandPlugins // {};
  });

  # Base pkgs used for dev shells and checks — no hyprland overlay
  # Hyprland overlay is applied conditionally via modules/nix/hyprland.nix
  mkPkgs = system:
    import nixpkgs {
      inherit system;
      overlays = [
        (hyprlandOverlay system)
        ((import ../packages/overlay.nix) inputs)
      ];
      config = import ./pkgs-config.nix;
    };

  mkCustomPkgs = pkgs: import ../packages/flake/custom-packages.nix { inherit pkgs; };
  mkIosevkaNeg = system: inputs."iosevka-neg".packages.${system};
in
{
  inherit mkPkgs mkCustomPkgs mkIosevkaNeg;
}
