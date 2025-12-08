{
  lib,
  stdenvNoCC,
  fetchzip,
}:
stdenvNoCC.mkDerivation rec {
  pname = "oldschool-pc-font-pack";
  version = "2.2";

  src = fetchzip {
    url = "https://int10h.org/oldschool-pc-fonts/download/oldschool_pc_font_pack_v2.2_linux.zip";
    hash = "sha256-54U8tZzvivTSOgmGesj9QbIgkSTm9w4quMhsuEc0Xy4=";
    stripRoot = false;
  };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    fontRoot="$out/share/fonts"
    mkdir -p "$fontRoot/truetype" "$fontRoot/opentype"

    while IFS= read -r file; do
      base="$(basename "$file")"
      case "$base" in
        *.otb|*.otf) dest="$fontRoot/opentype/$base" ;;
        *.ttf|*.ttc) dest="$fontRoot/truetype/$base" ;;
        *) continue ;;
      esac
      install -Dm644 "$file" "$dest"
    done < <(find "$src" -type f)

    docDir="$out/share/doc/${pname}"
    install -Dm644 "$src/LICENSE.TXT" "$docDir/LICENSE.TXT"
    install -Dm644 "$src/docs/documentation.pdf" "$docDir/documentation.pdf"
    install -Dm644 "$src/docs/font_list.pdf" "$docDir/font_list.pdf"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Oldschool PC Font Pack bitmap and outline fonts (Px437/PxPlus)";
    homepage = "https://int10h.org/oldschool-pc-fonts/";
    license = licenses.cc-by-sa-40;
    platforms = platforms.all;
  };
}
