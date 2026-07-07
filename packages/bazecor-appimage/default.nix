{
  appimageTools,
  fetchurl,
  lib,
}:
let
  version = "1.9.0";
  pname = "bazecor";
  src = fetchurl {
    url = "https://github.com/Dygmalab/Bazecor/releases/download/v${version}/Bazecor-${version}-x64.AppImage";
    hash = "sha256-PSzcUirHoUJtNRSHw/53f+eGK7IgU1JnRcLuArMZJ+w=";
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  meta = {
    description = "Bazecor — Dygma keyboard configurator (AppImage)";
    homepage = "https://github.com/Dygmalab/Bazecor";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "bazecor";
  };
}
