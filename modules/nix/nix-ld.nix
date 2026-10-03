##
# Module: nix/nix-ld
# Purpose: run foreign (non-Nix) dynamically linked binaries — GitHub release
# tarballs, AppImage payloads, vendored toolchains — without patchelf'ing each
# one. NixOS has no /lib64/ld-linux-x86-64.so.2, so a generic-Linux glibc
# binary aborts with "Could not start dynamically linked executable"; nix-ld
# installs that interpreter and an LD_LIBRARY_PATH with the libs such binaries
# expect.
# Key options: features.system.nixLd.enable (default true).
# Dependencies: pkgs (the runtime libraries exposed to foreign binaries).
{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.features.system.nixLd;
in
{
  config = mkIf cfg.enable {
    programs.nix-ld = {
      enable = true;
      libraries = [
        pkgs.stdenv.cc.cc.lib # libstdc++ / libgcc_s (C++ and cargo-built binaries)
        pkgs.zlib # libz (compression, most archive/zip tooling)
        pkgs.openssl # libssl / libcrypto (networked CLIs)
        pkgs.curl # libcurl (downloaders, installers)
        pkgs.ncurses # libtinfo / libncurses (TUIs such as p2pmux)
        pkgs.icu # libicuuc / libicui18n / libicudata (Node, Electron)
        pkgs.libxcrypt # libcrypt.so.1 (older prebuilt binaries)
        pkgs.libxml2 # libxml2 (XML-parsing installers)
        pkgs.util-linux.lib # libuuid / libblkid
        pkgs.alsa-lib # libasound (audio clients launched from a shipped bundle)
      ];
    };
  };
}
