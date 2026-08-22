{ inputs, nixpkgs, ... }:
let
  hyprlandOverlay =
    system:
    (_: prev: {
      inherit (inputs.xdg-desktop-portal-hyprland.packages.${system}) xdg-desktop-portal-hyprland;
      # NOTE: hy3 comes from nixpkgs 26.05 (0.55.0), built against the same
      # Hyprland 0.55.4 the system ships. The github:outfoxxed/hy3 flake input
      # tracks Hyprland 0.56+ and its .so fails to load here (undefined symbol
      # IModeAlgorithm::getFSHandler), so we deliberately do NOT override it.
      hyprlandPlugins = prev.hyprlandPlugins;
    });

  bintoolsBootstrapFix = _: prev: {
    bintools = prev.bintools // {
      passthru = (prev.bintools.passthru or { }) // {
        isFromBootstrapFiles =
          (prev.bintools.passthru.bintools.passthru.isFromMinBootstrap or false)
          || (prev.bintools.passthru.bintools.passthru.isFromBootstrapFiles or false);
      };
    };
  };

  mkPkgs =
    system:
    import nixpkgs {
      inherit system;
      overlays = [
        bintoolsBootstrapFix
        (hyprlandOverlay system)
        # Local overlay first (for packages not yet migrated)
        ((import ../packages/overlay.nix) inputs)
        # External package flake (github:neg-serg/nixos-pkgs)
        inputs.neg-pkgs.overlays.default
      ];
      config = {
        allowAliases = false;
        allowUnfree = true;
        doCheckByDefault = false;
        permittedInsecurePackages = [ "pzip-0.2.0" ];
      };
    };

  mkCustomPkgs = pkgs: import ../packages/flake/custom-packages.nix { inherit pkgs; };
in
{
  inherit mkPkgs mkCustomPkgs;
}
