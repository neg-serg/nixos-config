{
  lib,
  stdenvNoCC,
  inputs,
}:
stdenvNoCC.mkDerivation rec {
  pname = "px437-ibm-conv-e";
  version = "unstable-2021-05-31";

  src = inputs.self + "/fonts/Px437_IBM_Conv_e.ttf";

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    fontRoot="$out/share/fonts/truetype"
    mkdir -p "$fontRoot"
    install -Dm644 "$src" "$fontRoot/Px437_IBM_Conv_e.ttf"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Px437 IBM Conv E TrueType retro VGA font";
    homepage = "https://int10h.org/oldschool-pc-fonts/";
    license = licenses.cc-by-sa-40;
    platforms = platforms.all;
  };
}
