##
# Package: nn-ar
# Purpose: nn.ar — SuperCollider UGens for neural audio processing (Gianluca
#   Elia): load PyTorch models (.pt) in scsynth (NN, NNModel UGens + classes).
#   Links against libtorch from nixpkgs (libtorch-bin). Models are loaded at
#   runtime by the user (e.g. RAVE on /zero/ai).
# Source: https://github.com/elgiano/nn.ar
{
  lib,
  stdenv,
  cmake,
  fetchFromGitHub,
  libtorch-bin,
  scPluginFarm,
}:
stdenv.mkDerivation rec {
  pname = "nn-ar";
  version = "unstable-2026-06-07";

  src = fetchFromGitHub {
    owner = "elgiano";
    repo = "nn.ar";
    rev = "38bf0bf0a5f14c2e29b2dbf89980644684d45ebf";
    hash = "sha256-H391osxuw97+NrCuzyjgoqd7h5Bu78cfoy9PXdb68w4=";
  };

  nativeBuildInputs = [ cmake ];
  buildInputs = [ libtorch-bin ];

  cmakeFlags = [
    "-DSC_PATH=${scPluginFarm}"
    "-DSUPERNOVA=OFF"
    "-DSCSYNTH=ON"
    "-DNOVA_SIMD=OFF"
    "-DSYSTEM_TORCH=ON"
    "-DCMAKE_SKIP_RPATH=ON"
  ];

  # cmake installs into $out/nn.ar/ (Classes/, HelpSource/, *.so);
  # reorganize into the standard SC layout.
  postInstall = ''
    mkdir -p "$out/lib/SuperCollider/plugins"
    mkdir -p "$out/share/SuperCollider/extensions/nn.ar"
    find "$out/nn.ar" -maxdepth 1 -name '*.so' -exec mv {} "$out/lib/SuperCollider/plugins/" \;
    cp -r "$out/nn.ar"/Classes "$out/share/SuperCollider/extensions/nn.ar/" 2>/dev/null || true
    cp -r "$out/nn.ar"/HelpSource "$out/share/SuperCollider/extensions/nn.ar/" 2>/dev/null || true
    cp -r "$out/nn.ar"/Tests "$out/share/SuperCollider/extensions/nn.ar/" 2>/dev/null || true
    rm -rf "$out/nn.ar"
  '';

  meta = lib.mkMeta {
    description = "SuperCollider UGens for neural audio processing (PyTorch models in scsynth)";
    homepage = "https://github.com/elgiano/nn.ar";
    license = lib.licenses.gpl3Plus;
  };
}
