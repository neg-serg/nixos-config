{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "pleamar-calendar";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  # The tests are hermetic: khal is a temporary shell script on PATH, both APIs
  # are local TcpListeners, and the caches, XDG dirs and TMPDIR live under a
  # temporary directory. Run them in the package build instead of letting them
  # rot.
  doCheck = true;

  meta = lib.mkMeta {
    description = "pleamar calendar worker (khal, public holidays, production calendar, JSON lines)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "pleamar-calendar";
  };
}
