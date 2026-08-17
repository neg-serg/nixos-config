{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

stdenvNoCC.mkDerivation rec {
  pname = "ttf-code2002";
  version = "0.922";

  # Code2002 by James Kass — freeware Unicode font for Plane 2 (SIP):
  # rare CJK ideographs (CJK Extensions B–I, ~12 MB TTF).
  src = fetchurl {
    url = "https://code2001.com/CODE2002.ZIP";
    name = "code2002.zip"; # unpackPhase only recognizes lowercase .zip
    hash = "sha256-7qMGnENJ6s/2wP3e/yIeEl6Prs0wmPi6v8bCSStI7Dw=";
  };

  nativeBuildInputs = [ unzip ];

  # Zip contains CODE2002.TTF at the top level (no wrapping dir).
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm644 CODE2002.TTF $out/share/fonts/truetype/code2002/CODE2002.TTF
    runHook postInstall
  '';

  meta = with lib; {
    description = "Code2002 freeware Unicode TrueType font for Plane 2 (rare CJK ideographs)";
    homepage = "https://www.code2001.com/Code2002_page.htm";
    # Freeware: may be used freely, must not be altered.
    license = licenses.unfreeRedistributable;
    platforms = platforms.all;
    maintainers = [ ];
  };
}
