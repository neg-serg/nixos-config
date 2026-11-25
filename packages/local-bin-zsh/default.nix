##
# Package: local-bin-zsh
# Purpose: Rust ports of the last zsh helpers in `packages/local-bin/bin`:
#   iommu-info (list/reset IOMMU groups), music-rename (normalize the album
#   directory of music files through MPD/albumdetails), read_documents
#   (vicinae pick of ~/dw documents -> zathura), pl (fzf/vicinae pick ->
#   mpv + vid-info) and music-tui (fzf TUI over the MERT similarity index).
#   One multicall binary answers to all five names, so `~/.local/bin` points at
#   the store symlinks instead of rendering the zsh files (and the shared
#   `_localbin.sh` helper retires with them).
{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "local-bin-zsh";
  version = (lib.importTOML ./Cargo.toml).package.version;

  # `local-bin-core` is a path dependency, so the build source must contain both
  # directories; the tarball root then holds them side by side.
  src = lib.fileset.toSource {
    root = ./..;
    # allow-relative: the path dependency lives next to this package directory
    fileset = lib.fileset.union ./../local-bin-core ./.;
  };
  sourceRoot = "source/local-bin-zsh";

  cargoLock.lockFile = ./Cargo.lock;

  # One multicall binary; each command is an argv[0] name pointing at it.
  postInstall = ''
    for name in iommu-info music-rename read_documents pl music-tui; do
      ln -s local-bin-zsh "$out/bin/$name"
    done
  '';

  meta = lib.mkMeta {
    description = "Rust ports of the last zsh packages/local-bin/bin helpers (iommu-info, music-rename, read_documents, pl, music-tui), shipped as one multicall binary";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "iommu-info";
  };
}
