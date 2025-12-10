{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage rec {
  pname = "adguardian-term";
  version = "1.6.0";

  # Local checkout of https://github.com/Lissy93/AdGuardian-Term
  src = /home/neg/src/1st_level/AdGuardian-Term;

  cargoLock.lockFile = "${src}/Cargo.lock";
  cargoHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

  meta = with lib; {
    description = "Terminal-based, real-time traffic monitor for AdGuard Home";
    homepage = "https://github.com/Lissy93/AdGuardian-Term";
    license = licenses.mit;
    mainProgram = "adguardian";
    platforms = platforms.linux;
  };
}
