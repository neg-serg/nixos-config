{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

stdenvNoCC.mkDerivation rec {
  pname = "ttf-code2000";
  version = "1.176";

  # Code2000 by James Kass — shareware Unicode TrueType font with a very broad
  # script coverage (60k+ glyphs). The ZIP may be redistributed freely if intact.
  src = fetchurl {
    url = "https://code2001.com/CODE2000.ZIP";
    name = "code2000.zip"; # unpackPhase only recognizes lowercase .zip
    hash = "sha256-tTz4p32aoZL4bKWHnkYxC0VEag3rONlsrbLZ4PL7qnU=";
  };

  nativeBuildInputs = [ unzip ];

  # Zip contains CODE2000.TTF + CODE2000.HTM at the top level (no wrapping dir).
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm644 CODE2000.TTF $out/share/fonts/truetype/code2000/CODE2000.TTF
    runHook postInstall
  '';

  meta = with lib; {
    description = "Code2000 shareware Unicode TrueType font with broad script coverage";
    homepage = "https://www.code2001.com/code2000_page.htm";
    # Shareware: $5 registration expected after evaluation; the unaltered ZIP
    # itself may be copied and distributed freely.
    license = licenses.unfreeRedistributable;
    platforms = platforms.all;
    maintainers = [ ];
  };
}
