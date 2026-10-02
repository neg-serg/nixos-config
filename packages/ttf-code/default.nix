# Code200x Unicode font family by James Kass — one parameterized derivation.
#
# The four variants differ only in pname/version/URL/zip payload/description:
# each is a fetchurl + unzip + install of a single top-level .TTF, so the
# derivation is identical modulo those fields. The public attribute names are
# unchanged — packages/overlay.nix maps pkgs.ttf-code2000 … ttf-code20x3 onto
# `callPackage ./ttf-code { variant = …; }`.
#
# Code2000 is shareware: a $5 registration is expected after evaluation, but
# the unaltered ZIP may be copied and distributed freely. Code2001/2002/20X3
# are freeware: usable freely, must not be altered. All are redistributable
# unmodified.
{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
  variant,
}:

let
  variants = {
    ttf-code2000 = {
      version = "1.176";
      url = "https://code2001.com/CODE2000.ZIP";
      zip = "code2000"; # unpackPhase only recognizes lowercase .zip
      hash = "sha256-tTz4p32aoZL4bKWHnkYxC0VEag3rONlsrbLZ4PL7qnU=";
      file = "CODE2000.TTF";
      dir = "code2000";
      description = "Code2000 shareware Unicode TrueType font with broad script coverage";
      homepage = "https://www.code2001.com/code2000_page.htm";
    };
    ttf-code2001 = {
      version = "0.922";
      url = "https://code2001.com/CODE2001.ZIP";
      zip = "code2001";
      hash = "sha256-2otgWfwgTUqI5/7/ggPlCGzR1It+KObUOL84OgQqgOs=";
      file = "CODE2001.TTF";
      dir = "code2001";
      description = "Code2001 freeware Unicode TrueType font for Plane 1 (ancient/historic scripts)";
      homepage = "https://www.code2001.com/code2001.htm";
    };
    ttf-code2002 = {
      version = "0.922";
      url = "https://code2001.com/CODE2002.ZIP";
      zip = "code2002";
      hash = "sha256-7qMGnENJ6s/2wP3e/yIeEl6Prs0wmPi6v8bCSStI7Dw=";
      file = "CODE2002.TTF";
      dir = "code2002";
      description = "Code2002 freeware Unicode TrueType font for Plane 2 (rare CJK ideographs)";
      homepage = "https://www.code2001.com/Code2002_page.htm";
    };
    ttf-code20x3 = {
      version = "0.904";
      url = "https://code2001.com/CODE20X3.ZIP";
      zip = "code20x3";
      hash = "sha256-bOILFSwuO3DCtjUO3ynvNNEkILu9jpMRutTfskDfFRE=";
      file = "CODE20X3.TTF";
      dir = "code20x3";
      description = "Code20X3 freeware Unicode TrueType font for Plane 3 (CJK Extensions G/H)";
      homepage = "https://www.code2001.com/Code20X3_page.htm";
    };
  };
  v = variants.${variant};
in
stdenvNoCC.mkDerivation rec {
  pname = variant;
  version = v.version;

  src = fetchurl {
    inherit (v) url hash;
    name = "${v.zip}.zip";
  };

  nativeBuildInputs = [ unzip ];

  # Zip contains <FILE>.TTF at the top level (no wrapping dir).
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm644 ${v.file} $out/share/fonts/truetype/${v.dir}/${v.file}
    runHook postInstall
  '';

  meta = lib.mkMeta {
    inherit (v) description homepage;
    license = lib.licenses.unfreeRedistributable;
    platforms = lib.platforms.all;
  };
}
