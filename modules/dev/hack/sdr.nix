{
  lib,
  config,
  pkgs,
  ...
}:
let
  hackLib = import ./lib.nix { inherit lib config; };
  _packages = hackLib.filterPackages [
    pkgs.chirp # radio programming tool for handhelds
    pkgs.gnuradio # SDR processing toolkit
    pkgs.gqrx # Qt SDR receiver for quick scans
    pkgs.hackrf # firmware/tools for HackRF devices
    pkgs.inspectrum # offline signal analysis viewer
    pkgs.kalibrate-rtl # calibrate RTL-SDR ppm via GSM beacons
    pkgs.multimon-ng # decode pager/AX.25/etc.
    pkgs.rtl-sdr-librtlsdr # RTL-SDR driver utilities
    pkgs.urh # Universal Radio Hacker
  ];
in
{
  config = lib.mkIf hackLib.enabled {
    # environment.systemPackages = lib.mkAfter _packages;
  };
}
