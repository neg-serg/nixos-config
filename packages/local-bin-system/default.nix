##
# Package: local-bin-system
# Purpose: Rust ports of the system-level helpers from `packages/local-bin/bin`:
#   steam-cloud-fix, dsh-statusline, sw, shade, main-menu,
#   surfingkeys-extension-patch, dsh-url, qr, pdf2md, upstream-radar,
#   vsmlrt-models and nix-updates. One binary per former script, installed
#   under the script's own name, so `~/.local/bin` can point at the store paths
#   instead of rendering the shell files.
#
# The tests are hermetic: every external tool is a fake first on an otherwise
# empty PATH, HOME/TMPDIR/XDG point into a per-case temporary tree and the
# environment is cleared. LOCAL_BIN_SYSTEM_TEST_SHELL rewrites the fakes'
# `#!/bin/sh` line, because a build sandbox does not necessarily provide /bin/sh.
#
# pdf2md used to get `@DOCLING_BIN@` substituted into the installed shell file;
# the port compiles the same path in. Callers that can supply the docling
# environment pass it as `docling`; without it the binary falls back to
# `docling` on PATH (which is how the cargo tests run).
{
  lib,
  rustPlatform,
  bash,
  coreutils,
  docling ? null,
}:

rustPlatform.buildRustPackage {
  pname = "local-bin-system";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  # `coreutils` is for the tests: the fake `mv` in the steam-cloud-fix fixture
  # logs its argv and then execs the real coreutils binary so the moved tree can
  # be asserted.
  nativeBuildInputs = [ coreutils ];

  preCheck = ''
    export LOCAL_BIN_SYSTEM_TEST_SHELL=${bash}/bin/bash
  '';
  doCheck = true;

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
