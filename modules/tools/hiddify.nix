{
  pkgs,
  lib,
  config,
  ...
}:
let
  pname = "hiddify";
  version = "2.0.5";
  src = pkgs.fetchurl {
    url = "https://github.com/hiddify/hiddify-app/releases/download/v${version}/Hiddify-Linux-x64.AppImage";
    hash = "sha256-zVwSBiKYMK0GjrUpPQrd0PaexJ4F2D9TNS/Sk8BX4BE=";
  };
  appimageContents = pkgs.appimageTools.extract { inherit pname version src; };
in
{
  config = lib.mkIf (config.features.apps.hiddify.enable or false) {
    environment.systemPackages = [
      (pkgs.appimageTools.wrapType2 {
        inherit pname version src;
        extraPkgs = pkgs': [
          pkgs'.libsecret
          pkgs'.libepoxy
          pkgs'.gtk3
          pkgs'.glib
          pkgs'.nss
          pkgs'.nspr
          pkgs'.alsa-lib
          pkgs'.at-spi2-atk
          pkgs'.cups
          pkgs'.dbus
          pkgs'.libdrm
          pkgs'.libxkbcommon
          pkgs'.mesa
          pkgs'.pango
          pkgs'.cairo
          pkgs'.xorg.libX11
          pkgs'.xorg.libXcomposite
          pkgs'.xorg.libXdamage
          pkgs'.xorg.libXext
          pkgs'.xorg.libXfixes
          pkgs'.xorg.libXrandr
          pkgs'.xorg.libxcb
        ];
        extraInstallCommands = ''
          install -m 444 -D ${appimageContents}/hiddify.desktop $out/share/applications/hiddify.desktop
          install -m 444 -D ${appimageContents}/usr/share/icons/hicolor/256x256/apps/hiddify.png \
            $out/share/icons/hicolor/256x256/apps/hiddify.png
          substituteInPlace $out/share/applications/hiddify.desktop \
            --replace 'Exec=AppRun' 'Exec=${pname}'
        '';
      })
    ];
  };
}
