{
  lib,
  config,
  pkgs,
  ...
}: let
  enabled = config.features.secrets.enable or true;
  packages = [
    pkgs.yubikey-agent
    pkgs.yubikey-manager
    pkgs.yubikey-personalization
  ];
in {
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
