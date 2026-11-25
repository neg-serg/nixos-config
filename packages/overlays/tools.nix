{ inputs, paths }:
final: prev:
let
  callPkg = final.neg.functions.callPkg; # shared helper (functions.nix)
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
    # albumdetails, duf, termeverything and zsh-native-syntax are not defined
    # here: neg-pkgs (applied after this overlay) provides them under the same
    # names, so the local recipes were dead. Deleting them left every drvPath
    # unchanged.
    hwctl = callPkg (inputs.rust-pkgs + "/hwctl/package.nix") { }; # Hardware control CLI — CPU boost, V-Cache masks, Nuvoton fan control
    hypr-focus = callPkg (inputs.rust-pkgs + "/hypr-focus/package.nix") { }; # Rust-based window focus CLI — set window class on focused Hyprland window
    tidalctl = callPkg (inputs.rust-pkgs + "/tidalctl/package.nix") { }; # TidalCycles session controller — engine start/stop, editor, recording
    # The stale python-era copy in neg-serg/nixos-pkgs has no `vid-info`, so
    # this one keeps the explicit path into the rust-pkgs input.
    pretty_printer = callPkg (inputs.rust-pkgs + "/pretty-printer/package.nix") { }; # coloured ppinfo + vid-info
    rsmetrx = inputs.rsmetrx.packages.${prev.stdenv.hostPlatform.system}.default;
    # Extracted to github:neg-serg/tint, which owns the build and its tests.
    tint = inputs.tint.packages.${prev.stdenv.hostPlatform.system}.default; # Colouriser for CLI output — scanners + per-tool rulesets
    nixbuild-status = callPkg (inputs.rust-pkgs + "/nixbuild-status/package.nix") { }; # One-line NixOS build status for status bars (waybar/i3bar/polybar)
    lusty = callPkg (inputs.lusty.outPath) { }; # Native file/buffer picker for Neovim — external repo ~/src/main/@projects/lusty
    # Extracted to github:neg-serg/tgchat-rs, which owns the build and its tests.
    tgchat-rs = inputs.tgchat-rs.packages.${prev.stdenv.hostPlatform.system}.default; # Telegram chat access on a grammers user session (replaces the retired Telethon tgchat)
    # Extracted to github:neg-serg/music-index-tools, which owns the crate, its
    # packaging and the self-check; the host only consumes the package.
    music-index-tools = inputs.music-index-tools.packages.${prev.stdenv.hostPlatform.system}.default; # Build/query the MERT similarity index (music-index, music-similar; embeddings via music-embed)
    # Extracted to github:neg-serg/mpd-voice, which owns the crate, its packaging
    # and the flake checks; the host only consumes the package.
    mpd-voice = inputs.mpd-voice.packages.${prev.stdenv.hostPlatform.system}.default; # Voice control for MPD: microphone -> local STT -> player commands
    # Extracted to github:neg-serg/genlc, which owns the crate and its packaging.
    genlc = inputs.genlc.packages.${prev.stdenv.hostPlatform.system}.default; # Genelec SAM monitor control over the GLM USB adapter
    # Extracted to github:neg-serg/hypr-win-list, which owns the crate, its
    # packaging and the picker fixture check. Its wrapper prepends the binaries
    # the picker shells out to, so it must carry the host's patched vicinae and
    # its hyprland: the input's own nixpkgs copies would add a second launcher
    # and compositor to the closure.
    hypr-win-list = inputs.hypr-win-list.packages.${prev.stdenv.hostPlatform.system}.default.override {
      inherit (final) hyprland vicinae;
    }; # Hyprland window picker for vicinae dmenu
    # Extracted to github:neg-serg/telegram-notify, which owns the build and its tests.
    telegram-notify = inputs.telegram-notify.packages.${prev.stdenv.hostPlatform.system}.default; # Rust Telegram notification binaries (calendar, pill, bot, alert scanner/bridge, zfs watch)
    # Extracted to github:neg-serg/sing-box-proxy, which owns the build. The host
    # keeps the user unit, the secrets and the feature flag.
    sing-box-proxy = inputs.sing-box-proxy.packages.${prev.stdenv.hostPlatform.system}.default; # sing-box SOCKS proxy controller (on/off/status/refresh/gen/run)
    # Extracted to github:neg-serg/shtoy, which owns the crate, its packaging
    # and the CLI check. The host keeps the shader collection under
    # files/gui/shtoy and the local-bin symlink.
    shtoy = inputs.shtoy.packages.${prev.stdenv.hostPlatform.system}.default; # Run Shadertoy shaders fullscreen in esshader
  };
}
