##
# Package: ixiquarks
# Purpose: ixiQuarks — SC quark by thor/ixi: GUI instruments and effects
#   toolset (live coding oriented).
# Source: https://github.com/thormagnusson/ixiQuarks
{
  lib,
  mkScQuark,
}:
mkScQuark {
  pname = "ixiquarks";
  version = "unstable-2012-09-12";

  owner = "thormagnusson";
  repo = "ixiQuarks";
  rev = "18934fb87a256d53306f488687e19eb4c709b6fd";
  hash = "sha256-g5CxC89W0r/x24wRpFWr66Psaf7qsQzWgryFPR5Wdns=";

  installDir = "ixiQuarks";
  install = ''
    cp -r classes "$extdir/"
    cp -r help "$extdir/" 2>/dev/null || true
    cp -r README COPYING "$extdir/" 2>/dev/null || true
  '';

  meta = {
    description = "SuperCollider quark: GUI instruments and effects toolset";
    homepage = "https://github.com/thormagnusson/ixiQuarks";
    license = lib.licenses.gpl2Plus; # COPYING GPL
  };
}
