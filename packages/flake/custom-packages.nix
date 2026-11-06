{ pkgs, ... }:
{
  # Audio tools kept out of the system closure: `vital` is built on first use
  # by the vital-standalone unit, `flucoma` is materialised by
  # modules/media/audio/assets.nix for the SuperCollider plugin path.
  vital = pkgs.vital; # spectral wavetable synth (957 MiB closure)
  flucoma = pkgs.flucoma; # FluCoMa corpus-manipulation UGens for SuperCollider
  # Kept out of the system profile: yt-dlp drags a 692 MiB python closure.
  # The on-demand launcher (modules/user/nix-maid/web/yt-dlp.nix) builds this
  # attr on first use and GC-roots it under ~/.local/state/nix-apps.
  yt-dlp = pkgs.yt-dlp;
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
  aurora-tools = pkgs.neg.aurora-tools; # the headphone model catalogue CLI (aurora-camilla headphones)

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
  # On-demand companions of wineapps: the same toolchain, built by the launcher
  # on first use instead of sitting in the system closure (wine's own closure is
  # 1.7 GiB; the wineapps wrapper already embeds wine).
  wine = pkgs.wineWow64Packages.stable; # Wine runtime (on-demand launcher)
  yabridgectl = pkgs.yabridgectl; # VST bridge manager; its wrapper pins yabridge + wine
  lsp-plugins = pkgs.lsp-plugins; # Linux Studio Plugins (LV2/VST/VST3/CLAP) for Renoise
  dr14_tmeter = pkgs.dr14_tmeter; # DR14 dynamic-range meter (analysis CLI)
  carapace = pkgs.carapace; # multi-shell argument completer, called by zsh
  # Ollama's ROCm build: the service and the model-ensure script both reach it
  # through the on-demand launcher, so the 548 MiB closure sits in a GC root.
  ollama = pkgs.ollama-rocm; # the custom ROCm build (packages/ollama-qwen38)
  mangohud = pkgs.mangohud; # gaming HUD; launcher aliases mangoapp/mangohudctl/mangoplot
  winetricks = pkgs.winetricks; # Wine prefix setup helper (on-demand launcher)
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
      ${pkgs.telegram-desktop}/bin/Telegram "$@"
  '';

  # Wave 1 on-demand apps: aliases so the launchers in the system modules can
  # `nix build .#<attr>` without pulling the app into system-path.
  waylandar = pkgs.waylandar;
  renoise = pkgs.renoise;
  sioyek = pkgs.sioyek;
  vivaldi = pkgs.vivaldi-fixed;
  linux-firmware-minimal = pkgs.linux-firmware-minimal;
  difftastic = pkgs.difftastic;
  npins = pkgs.npins;
  nix-init = pkgs.nix-init;
  tshark = pkgs.tshark;
  strace-tui = pkgs.strace-tui; # syscall-trace explorer (TUI/JSON) for strace output
  galaxy-buds-client = pkgs.galaxy-buds-client;

  # Rarely used CLIs whose launchers live in the system modules: the first call
  # builds the package and registers a GC root under $HOME, so their closures
  # stay out of system-path (and out of every switch).
  sysdig = pkgs.sysdig;
  tmd-top = pkgs.tmd-top;
  amnezia-vpn = pkgs.amnezia-vpn;
  wayback = pkgs.wayback;
  lnav = pkgs.lnav;
  tdl = pkgs.tdl;
  scdl = pkgs.scdl;
  gh = pkgs.gh;
  gh-enhance = pkgs.gh-enhance;
  sherpa-onnx = pkgs.sherpa-onnx;
  neomutt = pkgs.neomutt; # terminal mail client (launcher in modules/user/mail.nix)
  perf = pkgs.perf; # linux perf tooling (launcher in modules/monitoring/pkgs)
  worktrunk = pkgs.worktrunk; # git worktree manager `wt` (launcher in modules/cli/dev.nix)

  # Docling (PDF/DOCX → Markdown with layout/table models): the python env is
  # ~3.9 GiB, so the `docling` launcher in modules/cli/ocr.nix builds it on
  # first use instead of carrying it in every system generation.
  docling-env = pkgs.neg.docling-env;

  # Audio/AV on-demand launchers: Surge XT (plugin, 609 MiB) is put on the
  # plugin path by the Renoise launcher, ffmpeg-full is the Vulkan/CUDA build.
  surge-xt = pkgs.surge-xt;
  realesrgan-ncnn-vulkan = pkgs.realesrgan-ncnn-vulkan;
  ffmpeg-full = pkgs.ffmpeg-full;

  # Audio content materialised once per user by modules/media/audio/assets.nix
  # into GC roots; the home-file symlinks point at $HOME, not at these paths.
  dirt-samples = pkgs.neg.dirt-samples;
  sc-faust = pkgs.sc-faust;
  renoise-redux = pkgs.neg.renoise-redux;

  # The full alsa-tools set (GTK/gst GUI utilities) — the system keeps only the
  # three RME HDSPe binaries, the rest is one `nix shell /etc/nixos#alsa-tools`
  # away.
  alsa-tools = pkgs.alsa-tools;

  # Manual proxy core; modules/system/net/proxy.nix wraps the service and the
  # CLI around this attr so the binary is built on first start/use.
  xray = pkgs.xray;

  # Piper + whisper.cpp + their python env and ffmpeg, merged into one root that
  # modules/media/audio/speech.nix materialises on first service start. The
  # overrides must match what that module used to install: inference only (no
  # torch/triton training extras, no Japanese dictionaries) and Vulkan whisper.
  speech-stack =
    let
      piper = pkgs.piper-tts.override {
        withTrain = false;
        withJapanese = false;
      };
      whisper = pkgs.whisper-cpp.override { vulkanSupport = true; };
      serverPy = pkgs.python3.withPackages (ps: [
        ps.fastapi
        ps.uvicorn
        ps.pydantic
        ps.python-multipart
      ]);
    in
    pkgs.symlinkJoin {
      name = "speech-stack";
      paths = [
        piper
        whisper
        serverPy
        pkgs.ffmpeg
      ];
    };
  # Desktop utilities built on first launch instead of at switch time; the
  # launchers live in modules/user/nix-maid/apps/gui-apps.nix.
  showmethekey = pkgs.showmethekey; # on-screen keystroke overlay for screencasts (GTK4 + libinput)
  localsend = pkgs.localsend; # AirDrop-style LAN file transfer (Flutter)
  losslesscut-bin = pkgs.losslesscut-bin; # lossless video/audio cutter (prebuilt Electron)
  vial = pkgs.vial;
  ddcui = pkgs.ddcui;
  virt-manager = pkgs.virt-manager;
  stable-diffusion-cpp = pkgs.stable-diffusion-cpp.override { vulkanSupport = true; };

  ocrmypdf =
    let
      tesseract = pkgs.tesseract.override {
        enableLanguages = [
          "eng"
          "rus"
          "osd"
        ];
      };
      unpaper = pkgs.unpaper.overrideAttrs {
        src = pkgs.fetchurl {
          url = "https://github.com/unpaper/unpaper/releases/download/unpaper-7.0.0/unpaper-7.0.0.tar.xz";
          hash = "sha256-JXX7vybCJxnRy4grWWAsmQDH90cRisEwiD9jQZvkaoA=";
        };
      };
    in
    pkgs.python3.pkgs.toPythonApplication (
      pkgs.python3.pkgs.ocrmypdf.override { inherit tesseract unpaper; }
    );

  # MERT similarity index tooling (Rust; embeddings come from music-embed).
  music-index-tools = pkgs.neg.music-index-tools;

  camillagui = pkgs.camillagui; # web GUI for CamillaDSP (backend + prebuilt React frontend)
  atrium = pkgs.atrium; # Wayland multiseat display manager
  wordcraft = pkgs.wordcraft; # Word-style word processor (.docx/.odt/.rtf) + converter CLI
  craft-anything = pkgs.craft-anything; # reverse-engineering workbench + rebuild assistant (GUI + CLI + MCP)
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
