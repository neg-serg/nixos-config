{
  lib,
  fetchFromGitHub,
  rustPlatform,
  pkg-config,
  openssl,
}:
rustPlatform.buildRustPackage rec {
  pname = "lucida-downloader";
  version = "0.1.7-unstable-2024-12-27";

  src = fetchFromGitHub {
    owner = "jelni";
    repo = "lucida-downloader";
    rev = "697aa27ad922194019cde87935bdc0e6b5330b3c"; # Latest commit from master
    hash = "sha256-f5cegAucJSiRekTAZBkrdn0HoEELvINN6Rd5Ehb7InA=";
  };

  cargoHash = "sha256-ADo0AuMsvd86ytlVStBXPJ9vFG/JeSm2kDMGM5VCqzA=";

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl ];

  meta = {
    description = "A multithreaded downloader for lucida.to";
    homepage = "https://github.com/jelni/lucida-downloader";
    license = lib.licenses.gpl3Only;
    mainProgram = "lucida";
    maintainers = [ ];
  };
}
