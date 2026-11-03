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
#
# The tests are hermetic: every external tool is a fake shell script first on
# an otherwise empty PATH, HOME/XDG/TMPDIR point into a per-case temporary tree,
# and the environment is cleared. LOCAL_BIN_ZSH_EXTRA_TEST_SHELL rewrites the
# fakes' `#!/bin/sh` line, because a build sandbox does not necessarily provide
# /bin/sh; LOCAL_BIN_ZSH_EXTRA_TEST_MKDIR lets the fake mkdir create the temp
# directories with the store coreutils instead of the host's /bin.
#
# Two test-only hooks keep the dangerous paths out of the suite:
# LOCAL_BIN_ZSH_EXTRA_LOOKING_GLASS points the Looking Glass checks at a fixture
# instead of /dev/shm/looking-glass, and LOCAL_BIN_ZSH_EXTRA_ASK_FILE answers
# the TTY-only `read -q` confirmations from a file (the suite never touches the
# real VM, disk, nvram, sysctl or /dev/shm).
{
  lib,
  rustPlatform,
  bash,
  coreutils,
}:

rustPlatform.buildRustPackage {
  pname = "local-bin-zsh-extra";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  # `coreutils` is for the tests: the fake mkdir delegates to the store binary
  # so init/prepare create their fixture directories without the host /bin.
  nativeBuildInputs = [ coreutils ];

  preCheck = ''
    export LOCAL_BIN_ZSH_EXTRA_TEST_SHELL=${bash}/bin/bash
    export LOCAL_BIN_ZSH_EXTRA_TEST_MKDIR=${coreutils}/bin/mkdir
    export LOCAL_BIN_ZSH_EXTRA_TEST_RM=${coreutils}/bin/rm
  '';
  doCheck = true;

  meta = lib.mkMeta {
    description = "Rust ports of the remaining zsh packages/local-bin/bin helpers (gh-issues-export, mpd_del_album, sx, sys-relief, vol, win-vm)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "win-vm";
  };
}
