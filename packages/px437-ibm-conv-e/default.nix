{
  lib,
  stdenvNoCC,
  fetchzip,
}:
stdenvNoCC.mkDerivation rec {
  pname = "px437-ibm-conv-e";
  version = "unstable-2021-05-31";

  src = fetchzip {
    url = "https://int10h.org/oldschool-pc-fonts/download/oldschool_pc_font_pack_v2.2_linux.zip";
    hash = "sha256-0nfpld0in6a3fsmq5d8i35587j0k3387slg7igfx46lkr7nc63dk";
    stripRoot = false;
  };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    fontRoot="$out/share/fonts/truetype"
    mkdir -p "$fontRoot"
    install -Dm644 "$src/ttf - Px (pixel outline)/Px437_IBM_Conv.ttf" \
      "$fontRoot/Px437_IBM_Conv.ttf"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Px437 IBM Conv TrueType retro VGA font";
    homepage = "https://int10h.org/oldschool-pc-fonts/";
    license = licenses.cc-by-sa-40;
    platforms = platforms.all;
  };
}
