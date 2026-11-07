{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.features.dev.unreal or { };
  devEnabled = config.lib.neg.enabled "dev";
  enabled = devEnabled && (cfg.enable or false);
  packagesInfo = import ./packages.nix { inherit lib pkgs; };
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packagesInfo.packages;
  };
}
