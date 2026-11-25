##
# Package: local-bin-system
# Purpose: Rust ports of the system-level helpers from `packages/local-bin/bin`:
#   steam-cloud-fix, dsh-statusline, sw, shade, main-menu,
#   surfingkeys-extension-patch, dsh-url, qr, pdf2md, upstream-radar,
#   vsmlrt-models and nix-updates. One binary per former script, installed
#   under the script's own name, so `~/.local/bin` can point at the store paths
#   instead of rendering the shell files.
#
# pdf2md used to get `@DOCLING_BIN@` substituted into the installed shell file;
# the port compiles the same path in. Callers that can supply the docling
# environment pass it as `docling`; without it the binary falls back to
# `docling` on PATH (the documented fallback).
{
  lib,
  rustPlatform,
  docling ? null,
}:

rustPlatform.buildRustPackage {
  pname = "local-bin-system";
  version = (lib.importTOML ./Cargo.toml).package.version;

  # `local-bin-core` is a path dependency, so the build source must contain both
  # directories; the tarball root then holds them side by side.
  src = lib.fileset.toSource {
    root = ./..;
    # allow-relative: the path dependency lives next to this package directory
    fileset = lib.fileset.union ./../local-bin-core ./.;
  };
  sourceRoot = "source/local-bin-system";

  cargoLock.lockFile = ./Cargo.lock;

  # One multicall binary; each command is an argv[0] name pointing at it.
  postInstall = ''
    for name in steam-cloud-fix dsh-statusline sw shade main-menu surfingkeys-extension-patch dsh-url qr pdf2md upstream-radar vsmlrt-models nix-updates; do
      ln -s local-bin-system "$out/bin/$name"
    done
  '';

  meta = lib.mkMeta {
    description = "Rust ports of the system-level packages/local-bin helpers (steam-cloud-fix, dsh-statusline, shade, main-menu, …)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "steam-cloud-fix";
  };
}
// lib.optionalAttrs (docling != null) {
  LOCAL_BIN_SYSTEM_DOCLING = "${docling}/bin/docling";
}
