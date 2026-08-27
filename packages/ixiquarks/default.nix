##
# Package: ixiquarks
# Purpose: ixiQuarks — SC quark by thor/ixi: GUI instruments and effects
#   toolset (live coding oriented).
# Source: https://github.com/thormagnusson/ixiQuarks
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation {
  pname = "ixiquarks";
  version = "unstable-2012-09-12";

  src = fetchFromGitHub {
    owner = "thormagnusson";
    repo = "ixiQuarks";
    rev = "18934fb87a256d53306f488687e19eb4c709b6fd";
    hash = "sha256-g5CxC89W0r/x24wRpFWr66Psaf7qsQzWgryFPR5Wdns=";
  };

  installPhase = ''
    runHook preInstall
    extdir="$out/share/SuperCollider/extensions/ixiQuarks"
    mkdir -p "$extdir"
    cp -r classes "$extdir/"
    cp -r help "$extdir/" 2>/dev/null || true
    cp -r README COPYING "$extdir/" 2>/dev/null || true
    runHook postInstall
  '';

  meta = with lib; {
    description = "SuperCollider quark: GUI instruments and effects toolset";
    homepage = "https://github.com/thormagnusson/ixiQuarks";
    license = licenses.gpl2Plus; # COPYING GPL
    platforms = platforms.all;
    maintainers = [ ];
  };
}
