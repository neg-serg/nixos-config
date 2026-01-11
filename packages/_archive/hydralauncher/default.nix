{
  lib,
  appimageTools,
  fetchurl,
}:
let
  pname = "hydralauncher";
  version = "3.2.3";

  src = fetchurl {
    url = "https://github.com/hydralauncher/hydra/releases/download/v${version}/hydralauncher-${version}.AppImage";
    hash = "sha256-iQL/xEyVgNfAeiz41sos8nbrGRxzQWR618EikPLS/Ig=";
  };

  appimageContents = appimageTools.extractType2 { inherit pname src version; };
in
appimageTools.wrapType2 {
  inherit pname src version;

  extraInstallCommands = ''
    install -Dm444 ${appimageContents}/usr/share/icons/hicolor/512x512/apps/hydralauncher.png \
      $out/share/icons/hicolor/512x512/apps/hydralauncher.png
    install -Dm444 ${appimageContents}/hydralauncher.desktop \
      $out/share/applications/hydralauncher.desktop
    substituteInPlace $out/share/applications/hydralauncher.desktop \
      --replace-fail 'Exec=AppRun' "Exec=$out/bin/hydralauncher"
  '';

  meta = with lib; {
    description = "Game launcher with embedded BitTorrent client";
    homepage = "https://github.com/hydralauncher/hydra";
    changelog = "https://github.com/hydralauncher/hydra/releases/tag/v${version}";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "hydralauncher";
    sourceProvenance = [ sourceTypes.binaryNativeCode ];
  };
}
