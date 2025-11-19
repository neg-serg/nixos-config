{
  lib,
  config,
  pkgs,
  ...
}: let
  hackLib = import ./lib.nix {inherit lib config;};
  packages = hackLib.filterPackages [
    pkgs.chirp
    pkgs.gnuradio
    pkgs.gqrx
    pkgs.hackrf
    pkgs.inspectrum
    pkgs.kalibrate-rtl
    pkgs.multimon-ng
    pkgs.rtl-sdr-librtlsdr
  ];
in {
  config = lib.mkIf hackLib.enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
