{ lib, rustPlatform }:

rustPlatform.buildRustPackage rec {
  pname = "pwroute";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = with lib; {
    description = "PipeWire audio router for RME HDSPe AIO Pro";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = licenses.mit;
    mainProgram = "pwroute";
    platforms = platforms.linux;
  };
}
