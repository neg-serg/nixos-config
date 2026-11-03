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
#
# The tests are hermetic: every external tool is a fake shell script first on
# an otherwise empty PATH, HOME/XDG/TMPDIR point into a per-case temporary
# tree, and the environment is cleared. LOCAL_BIN_ZSH_TEST_SHELL rewrites the
# fakes' `#!/bin/sh` line, because a build sandbox does not necessarily provide
# /bin/sh. LOCAL_BIN_ZSH_IOMMU_ROOT only exists for the tests: it points
# iommu-info at a fixture instead of the host's /sys/kernel/iommu_groups, so
# the suite never reads or resets real IOMMU groups.
{
  lib,
  rustPlatform,
  bash,
}:

rustPlatform.buildRustPackage {
  pname = "local-bin-zsh";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  preCheck = ''
    export LOCAL_BIN_ZSH_TEST_SHELL=${bash}/bin/bash
  '';
  doCheck = true;

  meta = lib.mkMeta {
    description = "Rust ports of the last zsh packages/local-bin/bin helpers (iommu-info, music-rename, read_documents, pl, music-tui)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "iommu-info";
  };
}
