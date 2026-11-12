{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage rec {
  pname = "hwctl";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "Hardware control CLI — CPU boost toggle, V-Cache mask recommendations, Nuvoton fan control";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "hwctl";
  };
}
