{ pkgs, ... }:
{
  adguardian-term = pkgs.adguardian;
  hxtools = pkgs.hxtools; # Collection of small tools over the years by j.eng

  rmpc = pkgs.rmpc; # TUI music player client for MPD with album art support vi...

  surfingkeys-pkg = pkgs.surfingkeys-pkg;
  rofi-config = pkgs.neg.rofi-config;

  wiremix = pkgs.wiremix;
}
