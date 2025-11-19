{
  lib,
  config,
  pkgs,
  ...
}: let
  devEnabled = config.features.dev.enable or false;
  packages = [
    pkgs.memtester
    pkgs.rewrk
    pkgs.stress-ng
    pkgs.vrrtest
    pkgs.wrk2
  ];
in {
  config = lib.mkIf devEnabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
