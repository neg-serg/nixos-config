{ lib, rustPlatform }:

rustPlatform.buildRustPackage rec {
  pname = "pwroute";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "PipeWire audio router for RME HDSPe AIO Pro";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "pwroute";
  };
}
