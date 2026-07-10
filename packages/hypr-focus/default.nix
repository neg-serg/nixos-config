{ lib, rustPlatform }:

rustPlatform.buildRustPackage rec {
  pname = "hypr-focus";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = with lib; {
    description = "Hyprland focus history tracker and window management CLI";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = licenses.mit;
    mainProgram = "hypr-focus";
    platforms = platforms.linux;
  };
}
