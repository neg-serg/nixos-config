##
# Package: local-bin-misc
# Purpose: Rust ports of the last shell helpers in `packages/local-bin/bin`:
#   pb (pastebin upload), any (pgrep -> ps), v (attach to the Neovim server or
#   start one), sclang-pwj (sclang under PipeWire-JACK) and renoise-pwj
#   (Renoise launcher). One multicall binary answers to all five names, so
#   `~/.local/bin` points at the store symlinks instead of rendering the shell
#   files.
{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "local-bin-misc";
  version = (lib.importTOML ./Cargo.toml).package.version;

  # `local-bin-core` is a path dependency, so the build source must contain both
  # directories; the tarball root then holds them side by side.
  src = lib.fileset.toSource {
    root = ./..;
    # allow-relative: the path dependency lives next to this package directory
    fileset = lib.fileset.union ./../local-bin-core ./.;
  };
  sourceRoot = "source/local-bin-misc";

  cargoLock.lockFile = ./Cargo.lock;

  # One multicall binary; each command is an argv[0] name pointing at it.
  postInstall = ''
    for name in pb any v sclang-pwj renoise-pwj; do
      ln -s local-bin-misc "$out/bin/$name"
    done
  '';

  meta = lib.mkMeta {
    description = "Rust ports of the last packages/local-bin/bin helpers (pb, any, v, sclang-pwj, renoise-pwj), shipped as one multicall binary";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "pb";
  };
}
