{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "transmission-exporter";
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "pborzenkov";
    repo = "transmission-exporter";
    rev = "v${version}";
    hash = "sha256-kx7pb1XpKRpX58hMYTXu/NXBoYrnZF1wcHMt1stkcog=";
  };

  vendorHash = "sha256-stHoGnv3me0q6XKStnPr1pWNv5okCFbjPuORUrRDYOw=";

  ldflags = ["-s" "-w"];

  meta = with lib; {
    description = "Prometheus exporter for Transmission BitTorrent client";
    homepage = "https://github.com/pborzenkov/transmission-exporter";
    license = licenses.mit;
    maintainers = with maintainers; [];
    mainProgram = "transmission-exporter";
  };
}
