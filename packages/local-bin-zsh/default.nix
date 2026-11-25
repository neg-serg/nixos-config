##
# Package: local-bin-zsh
# Purpose: Rust ports of the last zsh helpers in `packages/local-bin/bin`:
#   iommu-info (list/reset IOMMU groups), music-rename (normalize the album
#   directory of music files through MPD/albumdetails), read_documents
#   (vicinae pick of ~/dw documents -> zathura), pl (fzf/vicinae pick ->
#   mpv + vid-info) and music-tui (fzf TUI over the MERT similarity index).
#   One binary per former script, installed under the script's own name, so
#   `~/.local/bin` can point at the store paths instead of rendering the zsh
#   files (and the shared `_localbin.sh` helper retires with them).
{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "local-bin-zsh";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "Rust ports of the last zsh packages/local-bin/bin helpers (iommu-info, music-rename, read_documents, pl, music-tui)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "iommu-info";
  };
}
