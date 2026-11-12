##
# Package: local-bin-desktop
# Purpose: Rust ports of the desktop/media helpers that used to be shell
#   scripts in packages/local-bin/bin: pic-notify, screenrec, clip,
#   screenshot-toast, pic-info, pic-ocr, pic-dirs-list, wl-restore, unlock,
#   kitty-font-zoom, cursor-stretch, pngoptim and hypr-resize-proportional.
#
# One binary per installed command name, so `lib.getExe'` maps them directly.
# Every port keeps the original argument handling, help/usage bytes, the
# stdout/stderr split, exit codes and the external tools' argv; the tools stay
# subprocesses while argument parsing, path handling, JSON/formatting and state
# files are native.
#
# The tests are hermetic: every external tool is a fake shell script first on
# PATH, HOME/TMPDIR/XDG_RUNTIME_DIR point into a per-case temporary tree, and
# the environment is cleared. preCheck hands them the build's own bash (a build
# sandbox may not provide /bin/sh), a real `sleep` (screenrec's liveness window)
# and the coreutils the fakes use (`cat`) plus `sh` for clip's transform step.
{
  lib,
  rustPlatform,
  bash,
  coreutils,
}:

rustPlatform.buildRustPackage {
  pname = "local-bin-desktop";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  preCheck = ''
    export LOCAL_BIN_DESKTOP_TEST_SHELL=${bash}/bin/bash
    export LOCAL_BIN_DESKTOP_TEST_SLEEP=${coreutils}/bin/sleep
    export PATH=${coreutils}/bin:${bash}/bin:$PATH
  '';
  doCheck = true;

  meta = lib.mkMeta {
    description = "Rust ports of the desktop/media helpers from packages/local-bin/bin (pic-notify, screenrec, clip, screenshot-toast, pic-info, pic-ocr, pic-dirs-list, wl-restore, unlock, kitty-font-zoom, cursor-stretch, pngoptim, hypr-resize-proportional)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "pic-info";
  };
}
