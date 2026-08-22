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
        # Last overlay wins: neg-pkgs defines python3-lto from prev.python3
        # and drops the untangle src override, so re-apply the vendored-source
        # fix here (upstream tag was re-pushed → hash mismatch otherwise).
        (_final: prev: {
          python3-lto = prev.python3.override {
            packageOverrides = _pythonSelf: _pythonSuper: {
              enableOptimizations = true;
              enableLTO = true;
              reproducibleBuild = false;
              untangle = _pythonSuper.untangle.overrideAttrs (_: {
                src = ../files/sources/untangle-1.2.1.tar.gz;
              });
            };
          };
        })
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
