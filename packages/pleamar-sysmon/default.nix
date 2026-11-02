{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "pleamar-sysmon";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  # The tests are hermetic: synthetic /proc text, fake sysfs trees under a
  # temporary directory and a state file that is removed on drop. Run them in
  # the package build instead of letting them rot.
  doCheck = true;

  meta = lib.mkMeta {
    description = "pleamar system monitor worker (procfs/sysfs, JSON lines)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "pleamar-sysmon";
  };
}
