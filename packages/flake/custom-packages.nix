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

  omp = pkgs.neg.omp; # Oh My Pi (omp) — AI coding agent with LSP, DAP, subagents

  openagentscontrol = pkgs.neg.openagentscontrol; # AI agent framework for plan-first development (agents + contexts for OpenCode)

  hwctl = pkgs.neg.hwctl; # Hardware control CLI — CPU boost, V-Cache masks, Nuvoton fan control
  inferno = pkgs.neg.inferno; # Rust port of the FlameGraph profiling tool suite
  zestbay = pkgs.zestbay; # PipeWire patchbay with LV2/VST3/CLAP plugin hosting
  pw-audioshare = pkgs.pw-audioshare; # GTK4 PipeWire patchbay with auto-connect presets
}
