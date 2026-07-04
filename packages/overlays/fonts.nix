##
# Font derivations for fonts not available in nixpkgs.
# Ported from legacy Salt config (data/fonts.yaml).
_inputs: _final: prev:
let
  mkFont =
    {
      pname,
      url,
      hash,
    }:
    prev.stdenvNoCC.mkDerivation {
      inherit pname;
      version = "1";
      src = prev.fetchzip {
        inherit url hash;
        stripRoot = false;
      };
      installPhase = ''
        runHook preInstall
        mkdir -p $out/share/fonts/truetype
        find . -name '*.ttf' -exec cp -t $out/share/fonts/truetype {} \;
        mkdir -p $out/share/fonts/opentype
        find . -name '*.otf' -exec cp -t $out/share/fonts/opentype {} \; || true
        runHook postInstall
      '';
    };
in
{
  sf-pro-display = mkFont {
    pname = "sf-pro-display";
    url = "https://font.download/dl/font/sf-pro-display.zip";
    hash = "sha256-Vp8j4/i82rcJgkr1trbfpKSqmGTktANLcJcLSO428vI=";
  };

  anurati = mkFont {
    pname = "anurati";
    url = "https://font.download/dl/font/anurati.zip";
    hash = "sha256-ipNtWaXd61Pfmu5kETfY4+gb0mA5XIeEwHIxs/0lwQk=";
  };

  alfa-slab-one = mkFont {
    pname = "alfa-slab-one";
    url = "https://font.download/dl/font/alfa-slab-one.zip";
    hash = "sha256-0JKU1Pf/Zxfew6SGp0BZBwvyanSoIVmOYA6OzAFbmlE=";
  };
}
