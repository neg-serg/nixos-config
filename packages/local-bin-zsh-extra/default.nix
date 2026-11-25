##
# Package: local-bin-zsh-extra
# Purpose: Rust ports of the six remaining zsh helpers in
#   `packages/local-bin/bin`: gh-issues-export (GitHub issues with comments ->
#   Markdown/YAML for RAG), mpd_del_album (move the current MPD album to
#   ~/trash/music), sx (swayimg gallery launcher), sys-relief (drop caches and
#   lower IO/swap pressure, timed restore), vol (wpctl default-sink volume) and
#   win-vm (libvirt/QEMU Windows VM lifecycle manager).
#   One binary per former script, installed under the script's own name, so
#   `~/.local/bin` can point at the store paths instead of rendering the zsh
#   files.
{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "local-bin-zsh-extra";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "Rust ports of the remaining zsh packages/local-bin/bin helpers (gh-issues-export, mpd_del_album, sx, sys-relief, vol, win-vm)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "win-vm";
  };
}
