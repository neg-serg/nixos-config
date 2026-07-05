{ pkgs, ... }:
{
  adguardian-term = pkgs.adguardian;
  hxtools = pkgs.hxtools; # Collection of small tools over the years by j.eng

  rmpc = pkgs.rmpc; # TUI music player client for MPD with album art support vi...

  surfingkeys-pkg = pkgs.surfingkeys-pkg;
  rofi-config = pkgs.neg.rofi-config;
  sqlit = pkgs.neg.sqlit;

  waves = pkgs.waves;
  wiremix = pkgs.wiremix;
  palettum = pkgs.neg.palettum;

  gituserchrome = pkgs.gituserchrome;

  skwd = pkgs.skwd;

  exo = pkgs.exo; # Material 3 desktop shell for Ignis/Hyprland/Niri

  termeverything = pkgs.neg.termeverything;

  brrtfetch = pkgs.neg.brrtfetch;
  talktype = pkgs.neg.talktype;
}
