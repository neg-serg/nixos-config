{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

stdenvNoCC.mkDerivation rec {
  pname = "ttf-code2001";
  version = "0.922";

  # Code2001 by James Kass — freeware Unicode font for Plane 1 (SMP):
  # ancient/historic scripts (Linear B, Grantha, Gothic, Old Italic, Deseret,
  # Shavian, Osmanya, Cypriot, Phoenician, Ancient Greek Musical Notation, …).
  src = fetchurl {
    url = "https://code2001.com/CODE2001.ZIP";
    name = "code2001.zip"; # unpackPhase only recognizes lowercase .zip
    hash = "sha256-2otgWfwgTUqI5/7/ggPlCGzR1It+KObUOL84OgQqgOs=";
  };

  nativeBuildInputs = [ unzip ];

  # Zip contains CODE2001.TTF at the top level (no wrapping dir).
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm644 CODE2001.TTF $out/share/fonts/truetype/code2001/CODE2001.TTF
    runHook postInstall
  '';

  meta = with lib; {
    description = "Code2001 freeware Unicode TrueType font for Plane 1 (ancient/historic scripts)";
    homepage = "https://www.code2001.com/code2001.htm";
    # Freeware: may be used freely, must not be altered.
    license = licenses.unfreeRedistributable;
    platforms = platforms.all;
    maintainers = [ ];
  };
}
