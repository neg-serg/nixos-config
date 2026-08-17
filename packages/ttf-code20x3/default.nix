{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

stdenvNoCC.mkDerivation rec {
  pname = "ttf-code20x3";
  version = "0.904";

  # Code20X3 by James Kass (should have been called Code2003) — freeware Unicode
  # font for Plane 3 (TIP): CJK Extension G (4108/4939) and Extension H (2998/4192).
  src = fetchurl {
    url = "https://code2001.com/CODE20X3.ZIP";
    name = "code20x3.zip"; # unpackPhase only recognizes lowercase .zip
    hash = "sha256-bOILFSwuO3DCtjUO3ynvNNEkILu9jpMRutTfskDfFRE=";
  };

  nativeBuildInputs = [ unzip ];

  # Zip contains CODE20X3.TTF at the top level (no wrapping dir).
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm644 CODE20X3.TTF $out/share/fonts/truetype/code20x3/CODE20X3.TTF
    runHook postInstall
  '';

  meta = with lib; {
    description = "Code20X3 freeware Unicode TrueType font for Plane 3 (CJK Extensions G/H)";
    homepage = "https://www.code2001.com/Code20X3_page.htm";
    # Freeware: may be used freely, must not be altered.
    license = licenses.unfreeRedistributable;
    platforms = platforms.all;
    maintainers = [ ];
  };
}
