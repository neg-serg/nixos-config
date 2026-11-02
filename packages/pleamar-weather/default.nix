{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "pleamar-weather";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  # The tests are hermetic: every provider is a local TcpListener, the cache
  # and TMPDIR live under a temporary directory, and no test opens an external
  # socket. Run them in the package build instead of letting them rot.
  doCheck = true;

  meta = lib.mkMeta {
    description = "pleamar weather worker (Open-Meteo/MET Norway/wttr.in, JSON lines)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "pleamar-weather";
  };
}
