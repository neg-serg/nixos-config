{ inputs, nixpkgs, ... }:
let
  hyprlandOverlay = system: (_: prev: {
    inherit (inputs.xdg-desktop-portal-hyprland.packages.${system}) xdg-desktop-portal-hyprland;
    hyprlandPlugins = prev.hyprlandPlugins // {};
  });

  mkPkgs = system:
    import nixpkgs {
      inherit system;
      overlays = [
        (hyprlandOverlay system)
        ((import ../packages/overlay.nix) inputs)
      ];
      config = {
        allowAliases = false;
        allowUnfree = true;
        rocmSupport = true;
      };
    };

  mkCustomPkgs = pkgs: import ../packages/flake/custom-packages.nix { inherit pkgs; };
  mkIosevkaNeg = system: inputs."iosevka-neg".packages.${system};
in
{
  inherit mkPkgs mkCustomPkgs mkIosevkaNeg;
}
