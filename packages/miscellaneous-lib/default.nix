##
# Package: miscellaneous-lib
# Purpose: miSCellaneous_lib — SC quark by Alberto de Campo: patterns,
#   fx sequencing, granulation, wavesets, sieves, live coding utilities.
# Source: https://github.com/dkmayer/miSCellaneous_lib
{
  lib,
  mkScQuark,
}:
mkScQuark {
  pname = "miscellaneous-lib";
  version = "0.24-unstable-2020-07-08";

  owner = "dkmayer";
  repo = "miSCellaneous_lib";
  rev = "9c17f5565bb8c8afebdd293a6b0ed697a561aae6";
  hash = "sha256-q/hdh2lhXLDaF7xwKR9Hpx/YWt6+iCJHEicKb509ioI=";

  installDir = "miSCellaneous_lib";
  install = ''
    cp -r Classes "$extdir/"
    cp -r Help "$extdir/" 2>/dev/null || true
    cp -r HelpSource "$extdir/" 2>/dev/null || true
    cp -r Sounds "$extdir/" 2>/dev/null || true
    cp miSCellaneous_lib.quark LICENSE.txt "$extdir/" 2>/dev/null || true
  '';

  meta = {
    description = "SuperCollider quark: patterns, fx sequencing, granulation, wavesets, live coding utilities";
    homepage = "https://github.com/dkmayer/miSCellaneous_lib";
    license = lib.licenses.gpl2Plus;
  };
}
