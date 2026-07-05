{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
}:

rustPlatform.buildRustPackage rec {
  pname = "proteinview";
  version = "0.3.0";

  src = fetchFromGitHub {
    owner = "001TMF";
    repo = "ProteinView";
    rev = "v${version}";
    hash = "sha256-GH5+X6VjDdFy3SFPuEHsZ5iWMSPJGjzeXcPXL26IFg0=";
  };

  cargoHash = "sha256-x2qnUd1Lt5qpugETuR7ET+eDJ7jzub9O6BMBQxbIlVE=";

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl ];

  cargoBuildFlags = [ "--features" "fetch" ];
  cargoTestFlags = [ "--features" "fetch" ];

  doCheck = false; # test_nmr_multimodel_loads_single_model expects examples/*.pdb which are excluded from the package

  meta = with lib; {
    description = "Terminal protein structure viewer with interactive 3D visualization";
    homepage = "https://github.com/001TMF/ProteinView";
    license = licenses.mit;
    mainProgram = "proteinview";
    platforms = platforms.linux;
  };
}
