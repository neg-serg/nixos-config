{
  lib,
  config,
  pkgs,
  negLib,
  ...
}: let
  cfg = config.features.cli.zcli;
  repoRoot =
    if cfg.repoRoot != null
    then cfg.repoRoot
    else negLib.repoRoot;
  flakePath =
    if cfg.flakePath != null
    then cfg.flakePath
    else "${repoRoot}/flake.nix";
  zcliPkg = import ../../scripts/zcli.nix {
    inherit pkgs;
    profile = cfg.profile;
    inherit (cfg) backupFiles;
    repoRoot = toString repoRoot;
    flakePath = toString flakePath;
  };
in {
  config = lib.mkIf (cfg.enable or false) {
    home.packages = [
      zcliPkg
      pkgs.nh # Nix helper for flake rebuilds and cleanup
    ];
  };
}
