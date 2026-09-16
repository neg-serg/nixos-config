{ lib, rustPlatform }:

rustPlatform.buildRustPackage rec {
  pname = "hypr-focus";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "Hyprland focus history tracker and window management CLI";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "hypr-focus";
  };
}
