{
  lib,
  rustPlatform,
  bash,
}:

rustPlatform.buildRustPackage {
  pname = "local-bin-scripts";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  # The tests are hermetic: every external tool is a fake shell script first on
  # PATH, HOME/TMPDIR point into a per-case temporary tree, the environment is
  # cleared, and music-highlevel gets its extractor/playerctl stubbed. The
  # variable only rewrites the fakes' `#!/bin/sh` line, because a build sandbox
  # does not necessarily provide /bin/sh.
  preCheck = ''
    export LOCAL_BIN_SCRIPTS_TEST_SHELL=${bash}/bin/bash
  '';
  doCheck = true;

  meta = lib.mkMeta {
    description = "Rust ports of the packages/local-bin/scripts helpers (pass-2col, punzip, tty-log, journal-clean, music-highlevel)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "pass-2col";
  };
}
