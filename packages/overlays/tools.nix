{ inputs, paths }:
final: prev:
let
  callPkg = final.neg.functions.callPkg; # shared helper (functions.nix)
  pkg = final.neg.functions.pkg; # name → packages/<name>, no `../` counting
in
{
  # mprime (Prime95): the source zip on download.mersenne.ca / mersenne.org is
  # region-blocked (the fetcher gets a stub page instead of the zip). Vendored
  # tarball (relative-path pattern, see the vendored-tarball note in
  # overlays/vendored-sources.nix).
  mprime = prev.mprime.overrideAttrs (old: {
    # The stock package uses fetchzip (which unpacks during fetch); with a
    # vendored zip the generic unpackPhase needs unzip in nativeBuildInputs.
    src = paths.path "files/sources/mprime-31.04b02.source.zip";
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.unzip ];
    # The zip has files at its root (no single top dir); build from the root.
    sourceRoot = ".";
  });

  # ROCm (HIP) twin — Vulkan/RADV llama.cpp is pathologically slow on this host
  # (~0.2 tok/s for VRAM-resident models); ROCm is the working compute path.
  llama-cpp-qwen4exp-rocm = callPkg (pkg "llama-cpp-qwen4exp-rocm") { };

  # neg sub-attributes are merged once in packages/overlay.nix — no
  # `(prev.neg or {})` accumulation here (prev is the unmodified base).
  neg = rec {
    albumdetails = callPkg (pkg "albumdetails") { }; # Music album metadata CLI (used by music-rename script)
    brrtfetch = callPkg (pkg "brrtfetch") { }; # Animated ASCII art GIF renderer alongside sysinfo output
    duf = callPkg (pkg "duf") { }; # duf fork with --style plain, --no-header, --no-bars flags
    hwctl = callPkg (pkg "hwctl") { }; # Hardware control CLI — CPU boost, V-Cache masks, Nuvoton fan control
    iris = callPkg (pkg "iris") { }; # IRIS — shell auto-completion that works like code editor's IntelliSense
    oryx = callPkg (pkg "oryx") { }; # TUI for sniffing network traffic using eBPF (needs root + BTF kernel)
    omp = callPkg (pkg "omp") { }; # Oh My Pi (omp) — AI coding agent with LSP, DAP, subagents
    hypr-focus = callPkg (pkg "hypr-focus") { }; # Rust-based window focus CLI — set window class on focused Hyprland window
    niri-screen-time = callPkg (pkg "niri-screen-time") { }; # Screen time tracker by window class/title (niri + Hyprland daemon and report CLI)
    tidalctl = callPkg (pkg "tidalctl") { }; # TidalCycles session controller — engine start/stop, editor, recording
    pretty_printer = callPkg (pkg "pretty-printer") { }; # Pretty-printer library + CLI (ppinfo)
    rsmetrx = inputs.rsmetrx.packages.${prev.stdenv.hostPlatform.system}.default;
    termeverything = callPkg (pkg "termeverything") { }; # Run GUI windows inside your terminal (Wayland compositor → ANSI)
    zsh-native-syntax = callPkg (pkg "zsh-native-syntax") { }; # Native Rust-based zsh syntax highlighting engine
    rtpmidid = callPkg (pkg "rtpmidid") { }; # RTP-MIDI (AppleMIDI) daemon — ALSA seq <-> network MIDI (GLM VM bridge)
    flow = callPkg (pkg "flow") { }; # Terminal dashboard for real-time network throughput
    lsfg-vk = callPkg (pkg "lsfg-vk") { }; # Vulkan frame-gen layer (LSFG on Linux; needs Lossless Scaling on Steam)
    nixard = callPkg (pkg "nixard") { }; # TUI for exploring NixOS package closures / generating Nix declarations
    nixbuild-status = callPkg (pkg "nixbuild-status") { }; # One-line NixOS build status for status bars (waybar/i3bar/polybar)
    lusty = callPkg (inputs.lusty.outPath) { }; # Native file/buffer picker for Neovim — external repo ~/src/lusty
    tgchat = callPkg (pkg "tgchat") { }; # Telegram chat access via Telethon (read/send as the user)
    topowall = callPkg (pkg "topowall") { }; # Topographic contour wallpapers from real elevation data (GPU render)
    terrascope = callPkg (pkg "terrascope") { }; # Interactive world map for the terminal (braille; live weather/aircraft/earthquakes)
    geekbench-ai = callPkg (pkg "geekbench-ai") { }; # Geekbench AI — on-device inference benchmark (proprietary binary)
    neru = callPkg (pkg "neru") { }; # Desktop keyboard navigation — hints, grids, vim-style modes (upstream main)
  };
}
