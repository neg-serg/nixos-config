##
# Package: signalbox
# Purpose: SignalBox — SC3 quark by Joseph Anderson (ambisonictoolkit):
#   time/frequency-domain analysis and design tools (FreqSpectrum,
#   extSignal/extComplex methods, …). Pure sclang classes. Declared quark
#   dependency ExtraWindows is only for GUI helpers — not used by the classes.
# Source: https://github.com/ambisonictoolkit/SignalBox
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation {
  pname = "signalbox";
  version = "0.1.4-unstable-2019-09-12";

  src = fetchFromGitHub {
    owner = "ambisonictoolkit";
    repo = "SignalBox";
    rev = "387e87ebb83465623b1b0c786993eacea498ea8e";
    hash = "sha256-XwO4YB3CIvvoo/dPy9D3sMZBC62lVzoQ0ElgRUXwvco=";
  };

  installPhase = ''
    runHook preInstall
    extdir="$out/share/SuperCollider/extensions/SignalBox"
    mkdir -p "$extdir"
    cp -r Classes "$extdir/"
    cp -r HelpSource "$extdir/" 2>/dev/null || true
    cp SignalBox.quark "$extdir/" 2>/dev/null || true
    runHook postInstall
  '';

  meta = with lib; {
    description = "SuperCollider quark: time/frequency-domain analysis and design tools (SignalBox)";
    homepage = "https://github.com/ambisonictoolkit/SignalBox";
    license = licenses.gpl2Plus; # manifest says GPL
    platforms = platforms.all;
    maintainers = [ ];
  };
}
