{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "pleamar-calendar";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "pleamar calendar worker (khal, public holidays, production calendar, JSON lines)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "pleamar-calendar";
  };
}
