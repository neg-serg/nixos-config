{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "pleamar-journal";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  # The tests are hermetic: a fake journalctl/systemctl on PATH, a temporary
  # directory per case, and TZ pinned to a POSIX offset (no tzdata needed).
  # Run them in the package build instead of letting them rot.
  doCheck = true;

  meta = lib.mkMeta {
    description = "pleamar journal snapshot worker (journalctl, one JSON line)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "pleamar-journal";
  };
}
