{ pkgs, ... }:
{
  adguardian-term = pkgs.adguardian;
  hxtools = pkgs.hxtools; # Collection of small tools over the years by j.eng

  rmpc = pkgs.rmpc; # TUI music player client for MPD with album art support vi...

  waves = pkgs.waves;

  termeverything = pkgs.neg.termeverything;

  brrtfetch = pkgs.neg.brrtfetch;
  talktype = pkgs.neg.talktype;

  omp = pkgs.neg.omp; # Oh My Pi (omp) — AI coding agent with LSP, DAP, subagents

  hwctl = pkgs.neg.hwctl; # Hardware control CLI — CPU boost, V-Cache masks, Nuvoton fan control
  pw-audioshare = pkgs.pw-audioshare; # GTK4 PipeWire patchbay with auto-connect presets
  genlc = pkgs.genlc; # Genelec SAM loudspeaker CLI volume control via GLM USB adapter
  dsh = pkgs.neg.dsh;
}
