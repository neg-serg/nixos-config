{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "local-bin-scripts";
  version = (lib.importTOML ./Cargo.toml).package.version;

  # `local-bin-core` is a path dependency, so the build source must contain both
  # directories; `cleanSource ./.` would leave the dependency missing. The
  # tarball root then holds `local-bin-scripts/` next to `local-bin-core/`, hence
  # the explicit sourceRoot.
  src = lib.fileset.toSource {
    root = ./..;
    # allow-relative: the path dependency lives next to this package directory
    fileset = lib.fileset.union ./../local-bin-core ./.;
  };
  sourceRoot = "source/local-bin-scripts";

  cargoLock.lockFile = ./Cargo.lock;

  # One multicall binary; each command is an argv[0] name pointing at it.
  postInstall = ''
    for name in pass-2col punzip tty-log journal-clean music-highlevel; do
      ln -s local-bin-scripts "$out/bin/$name"
    done
  '';

  meta = lib.mkMeta {
    description = "Rust ports of the packages/local-bin/scripts helpers (pass-2col, punzip, tty-log, journal-clean, music-highlevel), shipped as one multicall binary";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "pass-2col";
  };
}
