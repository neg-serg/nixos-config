{
  lib,
  pkgs,
  config,
  negPaths ? {
    hmConfigRoot = ../..;
    repoRoot = (../..) + "/..";
    packagesRoot = ((../..) + "/..") + "/packages";
  },
  systemdUser ? import ./systemd-user.nix {inherit lib;},
  ...
}: let
  hmRepoPath = negPaths.hmConfigRoot;
  repoRoot = negPaths.repoRoot;
  packagesRoot = negPaths.packagesRoot;
  negLib = (import ./helpers.nix {
    inherit lib pkgs systemdUser packagesRoot;
  }) // {
    inherit hmRepoPath repoRoot packagesRoot;
  };
in {
  config.lib.neg = negLib;

  options.neg = {
    quickshell = {
      wrapperPackage = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        description = "Wrapped quickshell package (provides 'qs') with required QT/QML env prefixes.";
        example = "pkgs.callPackage ./path/to/wrapper.nix {}";
      };
    };

    rofi = {
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.rofi.override {
          plugins = [
            pkgs.rofi-file-browser
            pkgs.neg.rofi_games
          ];
        };
        description = "Rofi build with required plugins (file-browser, rofi-games).";
      };
    };
  };
}
