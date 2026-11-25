##
# Package: local-bin-zsh-extra
# Purpose: Rust ports of the six remaining zsh helpers in
#   `packages/local-bin/bin`: gh-issues-export (GitHub issues with comments ->
#   Markdown/YAML for RAG), mpd_del_album (move the current MPD album to
#   ~/trash/music), sx (swayimg gallery launcher), sys-relief (drop caches and
#   lower IO/swap pressure, timed restore), vol (wpctl default-sink volume) and
#   win-vm (libvirt/QEMU Windows VM lifecycle manager).
#   One multicall binary answers to all six names, so `~/.local/bin` points at
#   the store symlinks instead of rendering the zsh files.
{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "local-bin-zsh-extra";
  version = (lib.importTOML ./Cargo.toml).package.version;

  # `local-bin-core` is a path dependency, so the build source must contain both
  # directories; the tarball root then holds them side by side.
  src = lib.fileset.toSource {
    root = ./..;
    # allow-relative: the path dependency lives next to this package directory
    fileset = lib.fileset.union ./../local-bin-core ./.;
  };
  sourceRoot = "source/local-bin-zsh-extra";

  cargoLock.lockFile = ./Cargo.lock;

  # One multicall binary; each command is an argv[0] name pointing at it.
  postInstall = ''
    for name in gh-issues-export mpd_del_album sx sys-relief vol win-vm; do
      ln -s local-bin-zsh-extra "$out/bin/$name"
    done
  '';

  meta = lib.mkMeta {
    description = "Rust ports of the remaining zsh packages/local-bin/bin helpers (gh-issues-export, mpd_del_album, sx, sys-relief, vol, win-vm), shipped as one multicall binary";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "win-vm";
  };
}
