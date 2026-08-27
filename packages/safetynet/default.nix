##
# Package: safetynet
# Purpose: SafetyNet — SC quark by Alberto de Campo: protects against
#   dangerous/too-loud audio signals in live coding sessions.
# Source: https://github.com/adcxyz/SafetyNet
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation {
  pname = "safetynet";
  version = "unstable-2026-04-24";

  src = fetchFromGitHub {
    owner = "adcxyz";
    repo = "SafetyNet";
    rev = "276d3c3e9628df1882ade51ced20ccd8b06f4d32";
    hash = "sha256-2jTFphxrLMmY/Rk9cCyLb3UmOcPbXmCSNoyCGiyq6xA=";
  };

  installPhase = ''
    runHook preInstall
    extdir="$out/share/SuperCollider/extensions/SafetyNet"
    mkdir -p "$extdir"
    cp -r Classes "$extdir/"
    cp -r HelpSource "$extdir/"
    cp SafetyNet.quark README.md "$extdir/" 2>/dev/null || true
    runHook postInstall
  '';

  meta = with lib; {
    description = "SuperCollider quark: protects against dangerous audio signals in live coding";
    homepage = "https://github.com/adcxyz/SafetyNet";
    license = licenses.gpl3Plus;
    platforms = platforms.all;
    maintainers = [ ];
  };
}
