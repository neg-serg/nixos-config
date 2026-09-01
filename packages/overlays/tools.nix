inputs: final: prev:
let
  packagesRoot = inputs.self + "/packages";
  callPkg = final.neg.functions.callPkg; # shared helper (functions.nix)
in
{
  # mprime (Prime95): the source zip on download.mersenne.ca / mersenne.org is
  # region-blocked (the fetcher gets a stub page instead of the zip). Vendored
  # tarball (relative-path pattern, see carla in overlay.nix).
  mprime = prev.mprime.overrideAttrs (old: {
    # The stock package uses fetchzip (which unpacks during fetch); with a
    # vendored zip the generic unpackPhase needs unzip in nativeBuildInputs.
    src = ./../../files/sources/mprime-31.04b02.source.zip;
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.unzip ];
    # The zip has files at its root (no single top dir); build from the root.
    sourceRoot = ".";
  });

  # Qwen3.8-Flash-Next (qwen4exp arch) llama.cpp — experimental PR #27742
  # Vulkan build (+ graph_max_nodes patch); serves llama-server-flash-next.
  llama-cpp-qwen4exp = callPkg (packagesRoot + "/llama-cpp-qwen4exp") { };
  # ROCm (HIP) twin — Vulkan/RADV llama.cpp is pathologically slow on this host
  # (~0.2 tok/s for VRAM-resident models); ROCm is the working compute path.
  llama-cpp-qwen4exp-rocm = callPkg (packagesRoot + "/llama-cpp-qwen4exp-rocm") { };

  # neg sub-attributes are merged once in packages/overlay.nix — no
  # `(prev.neg or {})` accumulation here (prev is the unmodified base).
  neg = rec {
    albumdetails = callPkg (packagesRoot + "/albumdetails") { }; # Music album metadata CLI (used by music-rename script)
    brrtfetch = callPkg (packagesRoot + "/brrtfetch") { }; # Animated ASCII art GIF renderer alongside sysinfo output
    duf = callPkg (packagesRoot + "/duf") { }; # duf fork with --style plain, --no-header, --no-bars flags
    hwctl = callPkg (packagesRoot + "/hwctl") { }; # Hardware control CLI — CPU boost, V-Cache masks, Nuvoton fan control
    iris = callPkg (packagesRoot + "/iris") { }; # IRIS — shell auto-completion that works like code editor's IntelliSense
    oryx = callPkg (packagesRoot + "/oryx") { }; # TUI for sniffing network traffic using eBPF (needs root + BTF kernel)
    omp = callPkg (packagesRoot + "/omp") { }; # Oh My Pi (omp) — AI coding agent with LSP, DAP, subagents
    hypr-focus = callPkg (packagesRoot + "/hypr-focus") { }; # Rust-based window focus CLI — set window class on focused Hyprland window
    tidalctl = callPkg (packagesRoot + "/tidalctl") { }; # TidalCycles session controller — engine start/stop, editor, recording
    pretty_printer = callPkg (packagesRoot + "/pretty-printer") { }; # Pretty-printer library + CLI (ppinfo)
    rsmetrx = inputs.rsmetrx.packages.${prev.stdenv.hostPlatform.system}.default;
    talktype = callPkg (packagesRoot + "/talktype") { }; # Push-to-talk voice typing tool (F9 to record, transcribe, paste)
    termeverything = callPkg (packagesRoot + "/termeverything") { }; # Run GUI windows inside your terminal (Wayland compositor → ANSI)
    zsh-native-syntax = callPkg (packagesRoot + "/zsh-native-syntax") { }; # Native Rust-based zsh syntax highlighting engine
    rtpmidid = callPkg (packagesRoot + "/rtpmidid") { }; # RTP-MIDI (AppleMIDI) daemon — ALSA seq <-> network MIDI (GLM VM bridge)
    flow = callPkg (packagesRoot + "/flow") { }; # Terminal dashboard for real-time network throughput
    lsfg-vk = callPkg (packagesRoot + "/lsfg-vk") { }; # Vulkan frame-gen layer (LSFG on Linux; needs Lossless Scaling on Steam)
    nixard = callPkg (packagesRoot + "/nixard") { }; # TUI for exploring NixOS package closures / generating Nix declarations

    # ncpamixer-wrapped removed — nix-maid manages config via ~/.config/ncpamixer.conf
  };
}
