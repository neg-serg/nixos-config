##
# Package: local-bin-desktop
# Purpose: Rust ports of the desktop/media helpers that used to be shell
#   scripts in packages/local-bin/bin: pic-notify, screenrec, clip,
#   screenshot-toast, pic-info, pic-ocr, pic-dirs-list, wl-restore, unlock,
#   kitty-font-zoom, cursor-stretch, pngoptim and hypr-resize-proportional.
#
# One multicall binary; every installed command name is an argv[0] symlink to
# it, so `lib.getExe'` maps them directly.
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

  # `local-bin-core` is a path dependency, so the build source must contain both
  # directories; the tarball root then holds them side by side.
  src = lib.fileset.toSource {
    root = ./..;
    # allow-relative: the path dependency lives next to this package directory
    fileset = lib.fileset.union ./../local-bin-core ./.;
  };
  sourceRoot = "source/local-bin-desktop";

  cargoLock.lockFile = ./Cargo.lock;

  # One multicall binary; each command is an argv[0] name pointing at it.
  postInstall = ''
    for name in pic-notify screenrec clip screenshot-toast pic-info pic-ocr \
      pic-dirs-list wl-restore unlock kitty-font-zoom cursor-stretch pngoptim \
      hypr-resize-proportional; do
      ln -s local-bin-desktop "$out/bin/$name"
    done
  '';

  meta = lib.mkMeta {
    description = "Rust ports of the desktop/media helpers from packages/local-bin/bin (pic-notify, screenrec, clip, screenshot-toast, pic-info, pic-ocr, pic-dirs-list, wl-restore, unlock, kitty-font-zoom, cursor-stretch, pngoptim, hypr-resize-proportional), shipped as one multicall binary";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "pic-info";
  };
}
