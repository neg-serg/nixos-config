##
# Package: atk-sc3
# Purpose: ATK — Ambisonic Toolkit for SuperCollider: comprehensive First
#   Order Ambisonics soundfield tools (encoders, decoders, transformations,
#   analysis). Pure sclang quark; server UGens come from sc3-plugins (already
#   installed). Declared quark dependencies are satisfied by the other
#   packages (mathlib, filelog, hilbert, wslib, matrixarray?, signalbox,
#   sphericaldesign, pointview) — see the module wiring.
# Source: https://github.com/ambisonictoolkit/atk-sc3
{
  lib,
  mkScQuark,
}:
mkScQuark {
  pname = "atk-sc3";
  version = "5.0.7-unstable-2024-05-01";

  owner = "ambisonictoolkit";
  repo = "atk-sc3";
  rev = "b4dd8ca5eeac4558690d71697a5f9e3bf8ba2fe0";
  hash = "sha256-fq1j0lpT8Y4UhYRMXzwAQCIQfsAWRYokv+9jARg3mRU=";

  installDir = "atk-sc3";
  install = ''
    cp -r Classes "$extdir/"
    cp -r HelpSource "$extdir/"
    cp atk-sc3.quark LICENSE "$extdir/" 2>/dev/null || true
  '';

  meta = {
    description = "SuperCollider quark: Ambisonic Toolkit (First Order Ambisonics soundfield tools)";
    homepage = "https://github.com/ambisonictoolkit/atk-sc3";
    license = lib.licenses.gpl3Plus;
  };
}
