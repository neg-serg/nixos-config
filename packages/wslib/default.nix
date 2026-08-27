##
# Package: wslib
# Purpose: wslib — SC quark by Wouter Snoei: classes for lookahead patterns,
#   quantized busses, DJ-style helpers, file utilities.
# Source: https://github.com/supercollider-quarks/wslib
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation {
  pname = "wslib";
  version = "unstable-2026-06-29";

  src = fetchFromGitHub {
    owner = "supercollider-quarks";
    repo = "wslib";
    rev = "eeca6e46f158b795a41f80bec0626fc8593a7845";
    hash = "sha256-8COS+nj46naSXYeN06/v39p9FDJTsRByi7MDJ37sIl0=";
  };

  installPhase = ''
    runHook preInstall
    extdir="$out/share/SuperCollider/extensions/wslib"
    mkdir -p "$extdir"
    cp -r wslib-classes "$extdir/"
    cp -r wslib-help "$extdir/" 2>/dev/null || true
    cp wslib.quark "$extdir/" 2>/dev/null || true
    runHook postInstall
  '';

  meta = with lib; {
    description = "SuperCollider quark: lookahead patterns, quantized busses, DJ-style helpers";
    homepage = "https://github.com/supercollider-quarks/wslib";
    license = licenses.gpl2Plus;
    platforms = platforms.all;
    maintainers = [ ];
  };
}
