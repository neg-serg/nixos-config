{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage rec {
  pname = "rofiw";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = with lib; {
    description = "Rofi wrapper with auto-computed panel offsets from Quickshell theme + Hyprland monitor scale";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = licenses.mit;
    mainProgram = "rofiw";
    platforms = platforms.linux;
  };
}
