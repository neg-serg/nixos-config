{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage rec {
  pname = "solarust";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = with lib; {
    description = "A random solar system simulator for your terminal";
    license = licenses.mit;
    mainProgram = "solarust";
    platforms = platforms.unix;
  };
}
