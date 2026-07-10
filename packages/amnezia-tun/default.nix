{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage rec {
  pname = "amnezia-tun";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = with lib; {
    description = "AmneziaVPN config decoder — extracts sing-box compatible JSON";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = licenses.mit;
    mainProgram = "amnezia-tun";
    platforms = platforms.linux;
  };
}
