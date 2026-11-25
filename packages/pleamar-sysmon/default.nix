{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "pleamar-sysmon";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "pleamar system monitor worker (procfs/sysfs, JSON lines)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "pleamar-sysmon";
  };
}
