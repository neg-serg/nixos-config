{lib, config, pkgs, ...}: let
  enabled = config.features.torrent.enable or false;
  packages = [
    pkgs.transmission_4
    pkgs.bitmagnet
    pkgs.neg.bt_migrate
    pkgs.rustmission
    pkgs.curl
    pkgs.jq
    pkgs.jackett
  ];
in {
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
