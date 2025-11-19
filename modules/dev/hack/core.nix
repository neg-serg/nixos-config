{
  lib,
  config,
  pkgs,
  ...
}: let
  hackLib = import ./lib.nix {inherit lib config;};
  flags = config.features.dev.hack.core or {};
  groups = {
    secrets = [
      pkgs.gitleaks
      pkgs.git-secrets
    ];
    reverse = [
      pkgs.capstone
    ];
    crawl = [
      pkgs.katana
    ];
  };
  packages = hackLib.filterPackages (hackLib.mkGroupPackages flags groups);
in {
  config = lib.mkIf hackLib.enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
