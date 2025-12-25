{pkgs, ...}: let
  pname = "hiddify";
  version = "2.0.5";
  src = pkgs.fetchurl {
    url = "https://github.com/hiddify/hiddify-app/releases/download/v${version}/Hiddify-Linux-x64.AppImage";
    hash = "sha256-zVwSBiKYMK0GjrUpPQrd0PaexJ4F2D9TNS/Sk8BX4BE=";
  };
  appimageContents = pkgs.appimageTools.extract {inherit pname version src;};
in {
  environment.systemPackages = [
    (pkgs.appimageTools.wrapType2 {
      inherit pname version src;
      extraPkgs = pkgs:
        with pkgs; [
          libsecret
          libepoxy
          gtk3
          glib
          nss
          nspr
          alsa-lib
          at-spi2-atk
          cups
          dbus
          libdrm
          libxkbcommon
          mesa
          pango
          cairo
          xorg.libX11
          xorg.libXcomposite
          xorg.libXdamage
          xorg.libXext
          xorg.libXfixes
          xorg.libXrandr
          xorg.libxcb
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
}
