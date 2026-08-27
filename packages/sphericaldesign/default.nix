##
# Package: sphericaldesign
# Purpose: spherical design point sets for ambisonics — SC quark (ambisonictoolkit). Pure sclang classes.
#   Dependency of ATK.
# Source: https://github.com/ambisonictoolkit/SphericalDesign
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation {
  pname = "sphericaldesign";
  version = "unstable-2025-10-09";

  src = fetchFromGitHub {
    owner = "ambisonictoolkit";
    repo = "SphericalDesign";
    rev = "7a0a74cb9956d0281aaf44037ce4b3ee8a482dfc";
    hash = "sha256-ezN1yVCZshXZ6Yv41slJlBnpKKC/QcuMbqWuY/HzWzg=";
  };

  installPhase = ''
    runHook preInstall
    extdir="$out/share/SuperCollider/extensions/SphericalDesign"
    mkdir -p "$extdir"
    cp -r Classes "$extdir/"
    cp -r HelpSource "$extdir/" 2>/dev/null || true
    cp -r Designs "$extdir/" 2>/dev/null || true
    cp SphericalDesign.quark LICENSE "$extdir/" 2>/dev/null || true
    runHook postInstall
  '';

  meta = with lib; {
    description = "SuperCollider quark: spherical design point sets for ambisonics";
    homepage = "https://github.com/ambisonictoolkit/SphericalDesign";
    license = licenses.gpl2Plus;
    platforms = platforms.all;
    maintainers = [ ];
  };
}
