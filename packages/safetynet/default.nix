##
# Package: safetynet
# Purpose: SafetyNet — SC quark by Alberto de Campo: protects against
#   dangerous/too-loud audio signals in live coding sessions.
# Source: https://github.com/adcxyz/SafetyNet
{
  lib,
  mkScQuark,
}:
mkScQuark {
  pname = "safetynet";
  version = "unstable-2026-04-24";

  owner = "adcxyz";
  repo = "SafetyNet";
  rev = "276d3c3e9628df1882ade51ced20ccd8b06f4d32";
  hash = "sha256-2jTFphxrLMmY/Rk9cCyLb3UmOcPbXmCSNoyCGiyq6xA=";

  installDir = "SafetyNet";
  install = ''
    cp -r Classes "$extdir/"
    cp -r HelpSource "$extdir/"
    cp SafetyNet.quark README.md "$extdir/" 2>/dev/null || true
  '';

  meta = {
    description = "SuperCollider quark: protects against dangerous audio signals in live coding";
    homepage = "https://github.com/adcxyz/SafetyNet";
    license = lib.licenses.gpl3Plus;
  };
}
