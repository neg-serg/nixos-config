{
  lib,
  appimageTools,
  fetchurl,
}: let
  pname = "hiddify-app";
  version = "2.0.5";

  src = fetchurl {
    url = "https://github.com/hiddify/hiddify-app/releases/download/v${version}/Hiddify-Linux-x64.AppImage";
    hash = "sha256-zVwSBiKYMK0GjrUpPQrd0PaexJ4F2D9TNS/Sk8BX4BE=";
  };
in
  appimageTools.wrapType2 {
    inherit pname version src;

    meta = with lib; {
      description = "Multi-protocol proxy client (Hiddify App)";
      homepage = "https://github.com/hiddify/hiddify-app";
      license = licenses.cc-by-nc-sa-40;
      platforms = ["x86_64-linux"];
      mainProgram = "hiddify";
      sourceProvenance = with lib.sourceTypes; [binaryBytecode];
    };
  }
