{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:
rustPlatform.buildRustPackage rec {
  pname = "adguardian-term";
  version = "1.6.0";

  src = fetchFromGitHub {
    owner = "Lissy93";
    repo = "AdGuardian-Term";
    rev = "1.6.0";
    hash = "sha256-WxrSmCwLnXXs5g/hN3xWE66P5n0RD/L9MJpf5N2iNtY=";
  };

  cargoHash = "sha256-yPDysaslL/7N60eZ/hqZl5ZXIsof/pvlgHYfW1mIWtI=";

  # No extra system dependencies (built with rustls)
  meta = with lib; {
    description = "Terminal-based, real-time traffic monitor for AdGuard Home";
    homepage = "https://github.com/Lissy93/AdGuardian-Term";
    license = licenses.mit;
    mainProgram = "adguardian";
    platforms = platforms.linux;
  };
}
