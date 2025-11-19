{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.features.dev.unreal or {};
  devEnabled = config.features.dev.enable or false;
  enabled = devEnabled && (cfg.enable or false);
  useSteamRun = cfg.useSteamRun or true;
  packagesInfo = import ./packages.nix {inherit lib pkgs useSteamRun;};
in {
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packagesInfo.packages;
  };
}
