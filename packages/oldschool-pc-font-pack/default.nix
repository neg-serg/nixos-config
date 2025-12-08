{
  lib,
  stdenvNoCC,
  unzip,
  inputs,
}:
stdenvNoCC.mkDerivation rec {
  pname = "oldschool-pc-font-pack";
  version = "2.2";

  src = inputs.self + "/fonts/oldschool_pc_font_pack_v2.2_linux.zip";

  nativeBuildInputs = [unzip];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    workdir="$(mktemp -d)"
    unzip -qq "$src" -d "$workdir"

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
    done < <(find "$workdir" -type f)

    docDir="$out/share/doc/${pname}"
    install -Dm644 "$workdir/LICENSE.TXT" "$docDir/LICENSE.TXT"
    install -Dm644 "$workdir/docs/documentation.pdf" "$docDir/documentation.pdf"
    install -Dm644 "$workdir/docs/font_list.pdf" "$docDir/font_list.pdf"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Oldschool PC Font Pack bitmap and outline fonts (Px437/PxPlus)";
    homepage = "https://int10h.org/oldschool-pc-fonts/";
    license = licenses.cc-by-sa-40;
    platforms = platforms.all;
  };
}
