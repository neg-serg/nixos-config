{ inputs, nixpkgs, ... }:
let
  hyprlandOverlay =
    system:
    (_: prev: {
      inherit (inputs.xdg-desktop-portal-hyprland.packages.${system}) xdg-desktop-portal-hyprland;
      hyprlandPlugins = prev.hyprlandPlugins // { };
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
        # External package flake (github:neg-serg/nixos-pkgs) — base package set
        inputs.neg-pkgs.overlays.default
        # Local overlay last — overrides neg-pkgs for custom builds (e.g. opencode from flake source)
        ((import ../packages/overlay.nix) inputs)
      ];
      config = {
        allowAliases = false;
        allowUnfree = true;
        doCheckByDefault = false;
      };
    };

  mkCustomPkgs = pkgs: import ../packages/flake/custom-packages.nix { inherit pkgs; };
  mkIosevkaNeg = system: inputs."iosevka-neg".packages.${system};
in
{
  inherit mkPkgs mkCustomPkgs mkIosevkaNeg;
}
