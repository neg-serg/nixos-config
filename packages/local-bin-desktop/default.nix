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
{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "local-bin-desktop";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "Rust ports of the desktop/media helpers from packages/local-bin/bin (pic-notify, screenrec, clip, screenshot-toast, pic-info, pic-ocr, pic-dirs-list, wl-restore, unlock, kitty-font-zoom, cursor-stretch, pngoptim, hypr-resize-proportional)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "pic-info";
  };
}
