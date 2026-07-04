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
    hash = "sha256-XnP+Q77XdU4bGGn7s7Vzpexpe8VxikjBK0Yv6gzisqo=";
  };

  anurati = mkFont {
    pname = "anurati";
    url = "https://font.download/dl/font/anurati.zip";
    hash = "sha256-dmZpAWkryDUYA7YBc2D/T8s2KQVnEgJbtGHJr6arDj4=";
  };

  alfa-slab-one = mkFont {
    pname = "alfa-slab-one";
    url = "https://font.download/dl/font/alfa-slab-one.zip";
    hash = "sha256-nqU5fzlVEgHf0JR0zsV5fIuD7beEd8bTW+3SjOuf5m8=";
  };
}
