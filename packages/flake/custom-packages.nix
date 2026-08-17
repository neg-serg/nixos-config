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
  oryx = pkgs.neg.oryx; # TUI for sniffing network traffic using eBPF (needs root + BTF kernel)
  pw-audioshare = pkgs.pw-audioshare; # GTK4 PipeWire patchbay with auto-connect presets
  genlc = pkgs.genlc; # Genelec SAM loudspeaker CLI volume control via GLM USB adapter
  dsh = pkgs.neg.dsh;

  camillagui = pkgs.camillagui; # web GUI for CamillaDSP (backend + prebuilt React frontend)
  ttf-code2000 = pkgs.ttf-code2000; # Code2000 shareware Unicode TrueType font
  ttf-code2001 = pkgs.ttf-code2001; # Code2001 freeware font: Plane 1 ancient scripts
  ttf-code2002 = pkgs.ttf-code2002; # Code2002 freeware font: Plane 2 rare CJK
  ttf-code20x3 = pkgs.ttf-code20x3; # Code20X3 freeware font: Plane 3 CJK Ext G/H
}
