##
# Package: scmir
# Purpose: SCMIR — SuperCollider Music Information Retrieval library
#   (audio content analysis: onsets, pitch, chroma, MFCC) + CLI executables
#   (noveltycurve, similaritymatrix, gmm, hmm, NeuralNet). The SC classes
#   call the executables from SCMIRExtensions/scmirexec/.
# Source: https://github.com/sicklincoln/SCMIR
{
  lib,
  stdenv,
  gsl,
  openblas,
  fetchFromGitHub,
}:
stdenv.mkDerivation rec {
  pname = "scmir";
  version = "unstable-2025-05-28";

  src = fetchFromGitHub {
    owner = "sicklincoln";
    repo = "SCMIR";
    rev = "59ae32b9c2b331b1a561865def98b491a74bccb9";
    hash = "sha256-EcZ8yhxqAEkODyLscJf4MY4yEg7BFqvCEFF57wqwmpI=";
  };

  buildInputs = [
    gsl
    openblas # drop-in BLAS for gslcblas — multithreaded, AVX-512 on Zen 5
  ];

  # Offline batch analysis tools (not realtime audio) — safe to enable
  # fast-math and loop autoparallelism; -march=native targets Zen 5 (AVX-512).
  # OpenBLAS replaces the reference gslcblas for multithreaded matrix ops.
  cxxOpts = "-O3 -march=native -ffast-math -ftree-parallelize-loops=16 -floop-parallelize-all";

  buildPhase = ''
    runHook preBuild
    mkdir -p scmirexec
    g++ $cxxOpts Source/noveltycurve/noveltycurve.cpp -o scmirexec/noveltycurve
    g++ $cxxOpts Source/similaritymatrix/similarity.cpp -o scmirexec/similaritymatrix
    g++ $cxxOpts -std=gnu++14 Source/NeuralNet/ffnet.cpp Source/NeuralNet/main.cpp -o scmirexec/NeuralNet
    g++ $cxxOpts -std=gnu++14 Source/hmm/dhmm.cpp Source/hmm/main.cpp -o scmirexec/hmm \
      -L${gsl}/lib -lgsl -L${openblas}/lib -lopenblas -lm
    g++ $cxxOpts -std=gnu++14 -Wno-error=format-security Source/gmm/gmr.cpp Source/gmm/Macros.cpp \
      Source/gmm/Matrix.cpp Source/gmm/Vector.cpp Source/gmm/main.cpp -o scmirexec/gmm \
      -L${gsl}/lib -lgsl -L${openblas}/lib -lopenblas -lm
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    # SC classes look for executables at <Extensions>/SCMIRExtensions/scmirexec/
    extdir="$out/share/SuperCollider/extensions/SCMIRExtensions"
    mkdir -p "$extdir/scmirexec" "$extdir/Classes"
    install -m755 scmirexec/* "$extdir/scmirexec/"
    cp -r SCMIRExtensions/Classes/* "$extdir/Classes/"
    cp -r SCMIRExtensions/HelpSource "$extdir/" 2>/dev/null || true
    cp -r SCMIRExtensions/examples "$extdir/" 2>/dev/null || true
    cp COPYING "$extdir/" 2>/dev/null || true
    runHook postInstall
  '';

  meta = lib.mkMeta {
    description = "SuperCollider Music Information Retrieval library (analysis + CLI tools)";
    homepage = "https://github.com/sicklincoln/SCMIR";
    license = lib.licenses.gpl2Plus; # COPYING GPL
  };
}
