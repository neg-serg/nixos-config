##
# Package: local-bin-misc
# Purpose: Rust ports of the last shell helpers in `packages/local-bin/bin`:
#   pb (pastebin upload), any (pgrep -> ps), v (attach to the Neovim server or
#   start one), sclang-pwj (sclang under PipeWire-JACK) and renoise-pwj
#   (Renoise launcher). One binary per former script, installed under the
#   script's own name, so `~/.local/bin` can point at the store paths instead
#   of rendering the shell files.
#
# The tests are hermetic: every external tool is a fake shell script first on
# an otherwise empty PATH, HOME/XDG/TMPDIR point into a per-case temporary
# tree, and the environment is cleared. LOCAL_BIN_MISC_TEST_SHELL rewrites the
# fakes' `#!/bin/sh` line, because a build sandbox does not necessarily provide
# /bin/sh. `v` reads its socket path from LOCAL_BIN_MISC_V_SOCKET when set; the
# tests use it to keep their sockets inside the temporary tree instead of
# touching /tmp/nvim.sock.
{
  lib,
  rustPlatform,
  bash,
}:

rustPlatform.buildRustPackage {
  pname = "local-bin-misc";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  preCheck = ''
    export LOCAL_BIN_MISC_TEST_SHELL=${bash}/bin/bash
  '';
  doCheck = true;

  meta = lib.mkMeta {
    description = "Rust ports of the last packages/local-bin/bin helpers (pb, any, v, sclang-pwj, renoise-pwj)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "pb";
  };
}
