{ pkgs, ... }:
{
  adguardian-term = pkgs.adguardian;
  hxtools = pkgs.hxtools; # Collection of small tools over the years by j.eng

  pyprland_fixed = pkgs.pyprland_fixed;
  pyprland = pkgs.pyprland; # Hyperland plugin system

  rmpc = pkgs.rmpc; # TUI music player client for MPD with album art support vi...
  rtcqs = pkgs.neg.rtcqs;

  surfingkeys-pkg = pkgs.surfingkeys-pkg;
  two_percent = pkgs.neg.two_percent;
}
