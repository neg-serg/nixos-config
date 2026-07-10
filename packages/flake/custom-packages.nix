{ pkgs, ... }:
{
  adguardian-term = pkgs.adguardian;
  hxtools = pkgs.hxtools; # Collection of small tools over the years by j.eng

  rmpc = pkgs.rmpc; # TUI music player client for MPD with album art support vi...

  surfingkeys-pkg = pkgs.surfingkeys-pkg;
  sqlit = pkgs.neg.sqlit;

  waves = pkgs.waves;
palettum = pkgs.neg.palettum;

  skwd = pkgs.skwd;

  exo = pkgs.exo; # Material 3 desktop shell for Ignis/Hyprland/Niri

  termeverything = pkgs.neg.termeverything;

  brrtfetch = pkgs.neg.brrtfetch;
  talktype = pkgs.neg.talktype;

  proteinview = pkgs.neg.proteinview; # Terminal protein structure viewer with interactive 3D visualization

  openagentscontrol = pkgs.neg.openagentscontrol; # AI agent framework for plan-first development (agents + contexts for OpenCode)
}
