{ inputs, paths }:
final: prev:
let
  callPkg = final.neg.functions.callPkg; # shared helper (functions.nix)
  pkg = final.neg.functions.pkg; # name → packages/<name>, no `../` counting
in
{
  # mprime (Prime95): the source zip on download.mersenne.ca / mersenne.org is
  # region-blocked (the fetcher gets a stub page instead of the zip), so it is
  # republished in the public nixos-sources v1 release and pinned by hash (see
  # the vendored-tarball note in overlays/vendored-sources.nix).
  mprime = prev.mprime.overrideAttrs (old: {
    # The stock package uses fetchzip (which unpacks during fetch); with a
    # plain zip fetch the generic unpackPhase needs unzip in nativeBuildInputs.
    src = prev.fetchurl {
      url = "https://github.com/neg-serg/nixos-sources/releases/download/v1/mprime-31.04b02.source.zip";
      hash = "sha256-9raQlbY7CRybXQA/GBUK4Pat6mlzUV8+o9m7ErP/Tr0=";
    };
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.unzip ];
    # The zip has files at its root (no single top dir); build from the root.
    sourceRoot = ".";
  });

  # Herdr: tab appearance knobs (per-state colours and font style, title
  # templates, accent marker) are not in upstream 0.9.3 — packages/herdr/patches
  # carries the series that adds them (see its `series` file; applied in order).
  # The keys are inert in files/herdr/config.toml until a server built with the
  # series runs: the stock parser keeps the file loadable but reports each key
  # as unknown (`config check` -> "issues found", `server reload-config` ->
  # `partial`). A long-lived server keeps the parser it booted with, so the
  # patched build needs `herdr server live-handoff` to take effect.
  herdr = prev.herdr.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      (paths.path "packages/herdr/patches/0001-ui-per-state-tab-colours-and-font-styles.patch")
      (paths.path "packages/herdr/patches/0002-ui-tab-title-templates-and-the-active-marker.patch")
      (paths.path "packages/herdr/patches/0003-docs-document-the-tab-appearance-keys.patch")
    ];
  });

  # neg sub-attributes are merged once in packages/overlay.nix — no
  # `(prev.neg or {})` accumulation here (prev is the unmodified base).
  neg = rec {
    albumdetails = callPkg (pkg "albumdetails") { }; # Music album metadata CLI (used by music-rename script)
    dnsglobe = callPkg (pkg "dnsglobe") { }; # Global DNS propagation checker TUI — record answers on a world map
    duf = callPkg (pkg "duf") { }; # duf fork with --style plain, --no-header, --no-bars flags
    hwctl = callPkg (pkg "hwctl") { }; # Hardware control CLI — CPU boost, V-Cache masks, Nuvoton fan control
    oryx = callPkg (pkg "oryx") { }; # TUI for sniffing network traffic using eBPF (needs root + BTF kernel)
    hypr-focus = callPkg (pkg "hypr-focus") { }; # Rust-based window focus CLI — set window class on focused Hyprland window
    niri-screen-time = callPkg (pkg "niri-screen-time") { }; # Screen time tracker by window class/title (niri + Hyprland daemon and report CLI)
    tidalctl = callPkg (pkg "tidalctl") { }; # TidalCycles session controller — engine start/stop, editor, recording
    # Explicit path: `pkg` resolved this dir to a stale python-era copy.
    pretty_printer = callPkg (paths.path "packages/pretty-printer") { }; # coloured ppinfo + vid-info
    rsmetrx = inputs.rsmetrx.packages.${prev.stdenv.hostPlatform.system}.default;
    termeverything = callPkg (pkg "termeverything") { }; # Run GUI windows inside your terminal (Wayland compositor → ANSI)
    zsh-native-syntax = callPkg (pkg "zsh-native-syntax") { }; # Native Rust-based zsh syntax highlighting engine
    # Extracted to github:neg-serg/tint, which owns the build and its tests.
    tint = inputs.tint.packages.${prev.stdenv.hostPlatform.system}.default; # Colouriser for CLI output — scanners + per-tool rulesets
    flow = callPkg (pkg "flow") { }; # Terminal dashboard for real-time network throughput
    lsfg-vk = callPkg (pkg "lsfg-vk") { }; # Vulkan frame-gen layer (LSFG on Linux; needs Lossless Scaling on Steam)
    nixard = callPkg (pkg "nixard") { }; # TUI for exploring NixOS package closures / generating Nix declarations
    nixbuild-status = callPkg (pkg "nixbuild-status") { }; # One-line NixOS build status for status bars (waybar/i3bar/polybar)
    lusty = callPkg (inputs.lusty.outPath) { }; # Native file/buffer picker for Neovim — external repo ~/src/main/@projects/lusty
    # Extracted to github:neg-serg/tgchat-rs, which owns the build and its tests.
    tgchat-rs = inputs.tgchat-rs.packages.${prev.stdenv.hostPlatform.system}.default; # Telegram chat access on a grammers user session (replaces the retired Telethon tgchat)
    # Extracted to github:neg-serg/music-index-tools, which owns the crate, its
    # packaging and the self-check; the host only consumes the package.
    music-index-tools = inputs.music-index-tools.packages.${prev.stdenv.hostPlatform.system}.default; # Build/query the MERT similarity index (music-index, music-similar; embeddings via music-embed)
    # Extracted to github:neg-serg/mpd-voice, which owns the crate, its packaging
    # and the flake checks; the host only consumes the package.
    mpd-voice = inputs.mpd-voice.packages.${prev.stdenv.hostPlatform.system}.default; # Voice control for MPD: microphone -> local STT -> player commands
    # Extracted to github:neg-serg/telegram-notify, which owns the build and its tests.
    telegram-notify = inputs.telegram-notify.packages.${prev.stdenv.hostPlatform.system}.default; # Rust Telegram notification binaries (calendar, pill, bot, alert scanner/bridge, zfs watch)
    # Extracted to github:neg-serg/sing-box-proxy, which owns the build. The host
    # keeps the user unit, the secrets and the feature flag.
    sing-box-proxy = inputs.sing-box-proxy.packages.${prev.stdenv.hostPlatform.system}.default; # sing-box SOCKS proxy controller (on/off/status/refresh/gen/run)
    tuigram = callPkg (pkg "tuigram") { }; # Terminal UI Telegram client (npm package, Node 26 + node:ffi)
    topowall = callPkg (pkg "topowall") { }; # Topographic contour wallpapers from real elevation data (GPU render)
    terrascope = callPkg (pkg "terrascope") { }; # Interactive world map for the terminal (braille; live weather/aircraft/earthquakes)
    geekbench-ai = callPkg (pkg "geekbench-ai") { }; # Geekbench AI — on-device inference benchmark (proprietary binary)
    neru = callPkg (pkg "neru") { }; # Desktop keyboard navigation — hints, grids, vim-style modes (upstream main)
    uutils-sort = callPkg (pkg "uutils-sort") { }; # uu_sort patched to compute ICU collation keys in parallel
  };
}
