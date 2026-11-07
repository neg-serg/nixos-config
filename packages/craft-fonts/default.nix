# Shared font bundle of the ArtCraft suite (VectorCraft, FigCraft, SoundCraft,
# DeckCraft, GridCraft, SolidCraft). It is not an application: the apps' build
# scripts read the `fonts/manifest.txt` listed here through CRAFT_FONTS_DIR and
# embed those faces, which is what the official release packages ship.
#
# Upstream: https://github.com/storytold/craft-fonts. This shadows nixpkgs'
# `craft-fonts`, which is pinned to a 2026-10-11 revision: the newer apps need
# the faces and manifests added after it (deckcraft's simplified-Chinese
# manifest, gridcraft's NanumGothic and Noto Sans Symbols) and refuse to build
# with CRAFT_FONTS_REQUIRED otherwise. Bump the rev together with the app
# versions in packages/<app>/default.nix.
{
  lib,
  fetchFromGitHub,
  installFonts,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "craft-fonts";
  version = "0-unstable-2026-10-25";

  __structuredAttrs = true;
  strictDeps = true;

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "craft-fonts";
    rev = "aced4137c022f1f587624d48e81ec77e1914a9cc";
    hash = "sha256-5GjvL6EMCtOzK1/XbbzuBJDYpHC4SfBbOpGbPRjeME8=";
  };

  nativeBuildInputs = [ installFonts ];

  # Mirror upstream's tree under $out/fonts, symlinking the faces that
  # `installFonts` put in share/fonts/{truetype,opentype} instead of copying
  # them, so each face exists once in the closure. The manifests are installed
  # as-is: the build scripts parse them and expect the paths they list to exist
  # relative to CRAFT_FONTS_DIR.
  postInstall = ''
    install -d $out/fonts
    install -m644 fonts/*-manifest.txt fonts/manifest.txt $out/fonts/

    for dir in fonts/*/; do
      family=$(basename "$dir")
      install -d "$out/fonts/$family"
      for file in "$dir"*; do
        case $file in
          *.ttf) ln -s "$out/share/fonts/truetype/$(basename "$file")" "$out/fonts/$family/" ;;
          *.otf) ln -s "$out/share/fonts/opentype/$(basename "$file")" "$out/fonts/$family/" ;;
          *) install -m644 "$file" "$out/fonts/$family/" ;;
        esac
      done
    done
  '';

  meta = lib.mkMeta {
    description = "Shared font bundle for the ArtCraft application suite (CRAFT_FONTS_DIR input)";
    homepage = "https://github.com/storytold/craft-fonts";
    license = lib.licenses.AND [
      (lib.licenses.OR [
        lib.licenses.mit
        lib.licenses.asl20
      ])
      lib.licenses.ofl
    ];
  };
}
