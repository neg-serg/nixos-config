{
  lib,
  fetchurl,
  stdenvNoCC,
}:
let
  # Google Fonts ships Outfit only as a variable TTF (a `wght` axis covers
  # Thin..Black). Pinned to the last commit that touched ofl/outfit.
  rev = "8b0a1d0f5983c89bc2b93f1b5fb55f9e252744b5";

  ttf = fetchurl {
    name = "Outfit-Variable.ttf";
    url = "https://raw.githubusercontent.com/google/fonts/${rev}/ofl/outfit/Outfit%5Bwght%5D.ttf";
    hash = "sha256-/HKHJz5mkpd24rpU8UT+aZCAvsKfYb9knXDYcUaK6t4=";
  };

  license = fetchurl {
    name = "OFL.txt";
    url = "https://raw.githubusercontent.com/google/fonts/${rev}/ofl/outfit/OFL.txt";
    hash = "sha256-xnY1G/hXa5q6dDzV6qjA5+4NUfgF1yBEe0303bai5BY=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "outfit";
  version = "0-unstable-2026-03-12";

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/fonts/truetype
    cp ${ttf} $out/share/fonts/truetype/Outfit-Variable.ttf
    install -Dm644 ${license} $out/share/doc/outfit/OFL.txt

    runHook postInstall
  '';

  meta = {
    description = "Outfit geometric sans-serif variable font";
    homepage = "https://github.com/google/fonts/tree/main/ofl/outfit";
    license = lib.licenses.ofl;
    platforms = lib.platforms.all;
  };
}
