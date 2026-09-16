##
# Package: pointview
# Purpose: spherical point-view visualization tools — SC quark (ambisonictoolkit). Pure sclang classes.
#   Dependency of ATK.
# Source: https://github.com/ambisonictoolkit/PointView
{
  lib,
  mkScQuark,
}:
mkScQuark {
  pname = "pointview";
  version = "unstable-2020-08-30";

  owner = "ambisonictoolkit";
  repo = "PointView";
  rev = "fcdc03ce0c464c2d67809457ecff1adacdbe5be6";
  hash = "sha256-HSxO7KKvh51MYeZTTkgzAm/Wez/itk7N5uwVG9ex5TA=";

  installDir = "PointView";
  install = ''
    cp -r Classes "$extdir/"
    cp -r HelpSource "$extdir/" 2>/dev/null || true
    cp PointView.quark LICENSE "$extdir/" 2>/dev/null || true
  '';

  meta = {
    description = "SuperCollider quark: spherical point-view visualization tools";
    homepage = "https://github.com/ambisonictoolkit/PointView";
    license = lib.licenses.gpl2Plus;
  };
}
