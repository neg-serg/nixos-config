##
# Package: ddwchucklib
# Purpose: ddwChucklib — SC quark by James Harkins: support for advanced
#   algorithmic composition (Chuck browser, chucking patterns, MIDI GUI).
# Source: https://github.com/supercollider-quarks/ddwChucklib
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation {
  pname = "ddwchucklib";
  version = "unstable-2015-08-04";

  src = fetchFromGitHub {
    owner = "supercollider-quarks";
    repo = "ddwChucklib";
    rev = "da192ca20aa8ecdf6694dbbe656d0307105334fe";
    hash = "sha256-cU5ZPD8CgP/XhXHgRVcMQLrA68RDgWiA8vf1VBsGe8U=";
  };

  installPhase = ''
    runHook preInstall
    extdir="$out/share/SuperCollider/extensions/ddwChucklib"
    mkdir -p "$extdir"
    cp *.sc "$extdir/" 2>/dev/null || true
    cp -r Help "$extdir/" 2>/dev/null || true
    cp ddwChucklib.quark "$extdir/" 2>/dev/null || true
    runHook postInstall
  '';

  meta = with lib; {
    description = "SuperCollider quark: advanced algorithmic composition (Chuck browser, chucking)";
    homepage = "https://github.com/supercollider-quarks/ddwChucklib";
    license = licenses.gpl2Plus;
    platforms = platforms.all;
    maintainers = [ ];
  };
}
