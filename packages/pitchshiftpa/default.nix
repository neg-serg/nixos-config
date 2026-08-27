##
# Package: pitchshiftpa
# Purpose: PitchShiftPA — SC quark by Marcin Pączkowski (DXARTS/UW):
#   phase-aligned pitch and formant shifter (PSOLA/PAWS). Pure sclang classes
#   (PitchShiftPA, PitchShiftPARdWr) + help.
# Source: https://github.com/dyfer/PitchShiftPA
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation {
  pname = "pitchshiftpa";
  version = "unstable-2025-04-02";

  src = fetchFromGitHub {
    owner = "dyfer";
    repo = "PitchShiftPA";
    rev = "024e456625b723ad51696160920d721318080726";
    hash = "sha256-wFXKeppXopTtINNyLa2qPcHT4o7ts9Jn5lE4s+2D7/k=";
  };

  installPhase = ''
    runHook preInstall
    extdir="$out/share/SuperCollider/extensions/PitchShiftPA"
    mkdir -p "$extdir"
    cp -r Classes "$extdir/"
    cp -r HelpSource "$extdir/"
    cp PitchShiftPA.quark LICENSE "$extdir/" 2>/dev/null || true
    runHook postInstall
  '';

  meta = with lib; {
    description = "SuperCollider quark: phase-aligned pitch and formant shifter (PSOLA)";
    homepage = "https://github.com/dyfer/PitchShiftPA";
    license = licenses.gpl3Plus; # GPL-3.0 (LICENSE)
    platforms = platforms.all;
    maintainers = [ ];
  };
}
