{ pkgs, ... }:
{
  adguardian-term = pkgs.adguardian;
  hxtools = pkgs.hxtools; # Collection of small tools over the years by j.eng

  rmpc = pkgs.rmpc; # TUI music player client for MPD with album art support vi...

  waves = pkgs.waves;

  termeverything = pkgs.neg.termeverything;

  flow = pkgs.neg.flow; # terminal dashboard for real-time network throughput
  lsfg-vk = pkgs.neg.lsfg-vk; # Vulkan frame-gen layer (LSFG on Linux; CC BY-NC-ND, needs Lossless Scaling on Steam)
  nixard = pkgs.neg.nixard; # TUI for exploring NixOS package closures
  nixbuild-status = pkgs.neg.nixbuild-status; # one-line NixOS build status for status bars
  geekbench-ai = pkgs.neg.geekbench-ai; # Geekbench AI — on-device inference benchmark (unfree binary)
  neru = pkgs.neg.neru; # Desktop keyboard navigation: hints, grids, vim-style modes (upstream main)

  brrtfetch = pkgs.neg.brrtfetch;
  tint = pkgs.neg.tint; # colouriser for CLI output (scanners + per-tool rulesets)

  sola-mpd = pkgs.sola-mpd; # browser MPD client (Node backend + React UI)

  aurora = pkgs.neg.aurora; # aurora: local MPD player with a Vulkan UI (winit + ash + cosmic-text)

  mpd-voice = pkgs.mpd-voice; # voice control for MPD: local STT -> player commands (Rust)
  audio-cpp = pkgs.audio-cpp; # ggml audio runtime (Audio Flamingo Next, TTS, ASR) — prebuilt Vulkan build

  hwctl = pkgs.neg.hwctl; # Hardware control CLI — CPU boost, V-Cache masks, Nuvoton fan control
  lusty = pkgs.neg.lusty; # Native file/buffer picker for Neovim (Lusty successor)
  oryx = pkgs.neg.oryx; # TUI for sniffing network traffic using eBPF (needs root + BTF kernel)
  pw-audioshare = pkgs.pw-audioshare; # GTK4 PipeWire patchbay with auto-connect presets
  topowall = pkgs.neg.topowall; # Topographic contour wallpapers from real elevation data (GPU render)
  genlc = pkgs.genlc; # Genelec SAM loudspeaker CLI volume control via GLM USB adapter
  renoise-osc = pkgs.neg.renoise-osc; # OSC client for Renoise: Lua eval, transport, mixer, recording
  wineapps = pkgs.neg.wineapps; # declarative Wine app manager (list/install/uninstall/run)

  # pleamar scene runtime (the shell port's compiler and the plugin render gate).
  # `nix run .#pleamar -- --scene …` works without enabling features.gui.pleamar,
  # which is how the render gate reaches the binary when it is not on PATH.
  pleamar = pkgs.pleamar;

  dsh = pkgs.neg.dsh;

  camillagui = pkgs.camillagui; # web GUI for CamillaDSP (backend + prebuilt React frontend)
  atrium = pkgs.atrium; # Wayland multiseat display manager
  wordcraft = pkgs.wordcraft; # Word-style word processor (.docx/.odt/.rtf) + converter CLI
  sonda = pkgs.sonda; # file manager searching files by what they contain (EmbeddingGemma 2 on llama.cpp)
  graf = pkgs.graf; # terminal force-directed graph of markdown wikilinks (TUI)
  ttf-code2000 = pkgs.ttf-code2000; # Code2000 shareware Unicode TrueType font
  ttf-code2001 = pkgs.ttf-code2001; # Code2001 freeware font: Plane 1 ancient scripts
  ttf-code2002 = pkgs.ttf-code2002; # Code2002 freeware font: Plane 2 rare CJK
  ttf-code20x3 = pkgs.ttf-code20x3; # Code20X3 freeware font: Plane 3 CJK Ext G/H
}
