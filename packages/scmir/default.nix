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

  buildInputs = [ gsl ];

  buildPhase = ''
    runHook preBuild
    mkdir -p scmirexec
    g++ -O2 Source/noveltycurve/noveltycurve.cpp -o scmirexec/noveltycurve
    g++ -O2 Source/similaritymatrix/similarity.cpp -o scmirexec/similaritymatrix
    g++ -O2 -std=gnu++14 Source/NeuralNet/ffnet.cpp Source/NeuralNet/main.cpp -o scmirexec/NeuralNet
    g++ -O2 -std=gnu++14 Source/hmm/dhmm.cpp Source/hmm/main.cpp -o scmirexec/hmm \
      -L${gsl}/lib -lgsl -lgslcblas -lm
    g++ -O2 -std=gnu++14 -Wno-error=format-security Source/gmm/gmr.cpp Source/gmm/Macros.cpp \
      Source/gmm/Matrix.cpp Source/gmm/Vector.cpp Source/gmm/main.cpp -o scmirexec/gmm \
      -L${gsl}/lib -lgsl -lgslcblas -lm
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

  meta = with lib; {
    description = "SuperCollider Music Information Retrieval library (analysis + CLI tools)";
    homepage = "https://github.com/sicklincoln/SCMIR";
    license = licenses.gpl2Plus; # COPYING GPL
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
