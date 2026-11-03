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
  minibbs = pkgs.neg.minibbs; # tiny BBS-style message board (SQLite + HTTP)
  gen-unbound-hosts = pkgs.neg.local-bin-tools; # regenerate hosts/trantor/unbound-hosts.nix
  fetch-covers = pkgs.neg.local-bin-tools; # album covers for ~/music via sacad

  # pleamar scene runtime (the shell port's compiler and the plugin render gate).
  # `nix run .#pleamar -- --scene …` works without enabling features.gui.pleamar,
  # which is how the render gate reaches the binary when it is not on PATH.
  pleamar = pkgs.pleamar;

  # Animated nixie-tube renderer; also ships `nixie-metrics`, the screenshot
  # measurer the A1..A7 acceptance criteria are stated in.
  nixie = pkgs.nixie;

  # Theme pipeline (cargo tests run in the package checkPhase).
  pleamar-theme = pkgs.neg.pleamar-theme;

  # Developer harnesses (measure, describe-snap, smoke).
  pleamar-harness = pkgs.neg.pleamar-harness;

  # D-Bus fixtures for the pleamar engine tests (MPRIS player, nested tray item).
  pleamar-fixtures = pkgs.neg.pleamar-fixtures;

  dsh = pkgs.neg.dsh;

  # GUI apps deliberately kept out of the system closure. The launchers in
  # modules/user/session/chat.nix build these on first run and register a GC
  # root under $HOME, so the app bytes never enter system-path.
  telegram-desktop = pkgs.telegram-desktop;
  telegram-desktop-proxy = pkgs.writeShellScriptBin "telegram-desktop-proxy" ''
    exec ${pkgs.proxychains}/bin/proxychains4 -q \
      ${pkgs.telegram-desktop}/bin/telegram-desktop "$@"
  '';

  # MERT similarity index tooling (Rust; embeddings come from music-embed).
  music-index-tools = pkgs.neg.music-index-tools;

  camillagui = pkgs.camillagui; # web GUI for CamillaDSP (backend + prebuilt React frontend)
  atrium = pkgs.atrium; # Wayland multiseat display manager
  wordcraft = pkgs.wordcraft; # Word-style word processor (.docx/.odt/.rtf) + converter CLI
  sonda = pkgs.sonda; # file manager searching files by what they contain (EmbeddingGemma 2 on llama.cpp)
  graf = pkgs.graf; # terminal force-directed graph of markdown wikilinks (TUI)
  ttf-code2000 = pkgs.ttf-code2000; # Code2000 shareware Unicode TrueType font
  ttf-code2001 = pkgs.ttf-code2001; # Code2001 freeware font: Plane 1 ancient scripts
  ttf-code2002 = pkgs.ttf-code2002; # Code2002 freeware font: Plane 2 rare CJK
  ttf-code20x3 = pkgs.ttf-code20x3; # Code20X3 freeware font: Plane 3 CJK Ext G/H

  # Candidate Nix (2.35 + eval-speedup patches) — `nix build .#nix-eval-patched`.
  # Not `nix.package`: see the header comment of packages/nix-eval-patched.
  nix-eval-patched = pkgs.nix-eval-patched;

  # Determinate Nix 3.23.3 with PGO + eval-speedup patches —
  # `nix build .#nix-det-pgo`. Reaches `nix.package` only through
  # `features.nix.pgoNix.enable` (default off).
  nix-det-pgo = pkgs.nix-det-pgo;
}
