##
# Package: pointview
# Purpose: spherical point-view visualization tools — SC quark (ambisonictoolkit). Pure sclang classes.
#   Dependency of ATK.
# Source: https://github.com/ambisonictoolkit/PointView
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation {
  pname = "pointview";
  version = "unstable-2020-08-30";

  src = fetchFromGitHub {
    owner = "ambisonictoolkit";
    repo = "PointView";
    rev = "fcdc03ce0c464c2d67809457ecff1adacdbe5be6";
    hash = "sha256-HSxO7KKvh51MYeZTTkgzAm/Wez/itk7N5uwVG9ex5TA=";
  };

  installPhase = ''
    runHook preInstall
    extdir="$out/share/SuperCollider/extensions/PointView"
    mkdir -p "$extdir"
    cp -r Classes "$extdir/"
    cp -r HelpSource "$extdir/" 2>/dev/null || true
    cp PointView.quark LICENSE "$extdir/" 2>/dev/null || true
    runHook postInstall
  '';

  meta = with lib; {
    description = "SuperCollider quark: spherical point-view visualization tools";
    homepage = "https://github.com/ambisonictoolkit/PointView";
    license = licenses.gpl2Plus;
    platforms = platforms.all;
    maintainers = [ ];
  };
}
