{
  lib,
  config,
  pkgs,
  ...
}: let
  webEnabled = (config.features.web.enable or false) || (config.features.web.yandex.enable or false);
in {
  # imports = [inputs.yandex-browser.nixosModules.system];

  config = lib.mkIf webEnabled {
    environment.systemPackages = let
      yandex-browser-stable = pkgs.stdenv.mkDerivation rec {
        pname = "yandex-browser-stable";
        version = "25.10.1.1173-1";
        src = pkgs.fetchurl {
          url = "http://repo.yandex.ru/yandex-browser/deb/pool/main/y/yandex-browser-stable/yandex-browser-stable_${version}_amd64.deb";
          sha256 = "0r5a6ylwmd69qkhaxvgd4scl55miv7m244w4sk2cj3msa1gibv1i";
        };

        nativeBuildInputs = [pkgs.autoPatchelfHook pkgs.wrapGAppsHook3];
        buildInputs = with pkgs; [
          flac
          harfbuzzFull
          nss
          snappy
          xdg-utils
          alsa-lib
          atk
          cairo
          cups
          curl
          dbus
          expat
          fontconfig
          freetype
          gdk-pixbuf
          glib
          gtk3
          xorg.libX11
          xorg.libXcomposite
          xorg.libXcursor
          xorg.libXdamage
          xorg.libXext
          xorg.libXfixes
          xorg.libXi
          xorg.libXrandr
          xorg.libXrender
          xorg.libXtst
          libdrm
          libnotify
          libopus
          libuuid
          xorg.libxcb
          mesa
          nspr
          pango
          systemd
          at-spi2-atk
          at-spi2-core
          xorg.libxshmfence
        ];

        autoPatchelfIgnoreMissingDeps = [
          "libQt5Core.so.5"
          "libQt5Gui.so.5"
          "libQt5Widgets.so.5"
          "libQt6Core.so.6"
          "libQt6Gui.so.6"
          "libQt6Widgets.so.6"
        ];

        unpackPhase = ''
          ar x $src
          tar -xvf data.tar.xz
        '';

        installPhase = ''
          mkdir -p $out/bin
          cp -av opt/yandex/browser/* $out/

          # Copy desktop file (copy to dir, don't rename yet)
          mkdir -p $out/share/applications
          cp -v usr/share/applications/*.desktop $out/share/applications/

          # Fix path in all desktop files found
          substituteInPlace $out/share/applications/*.desktop \
            --replace /usr/bin/yandex-browser-stable $out/bin/yandex-browser-stable

          # Ensure binary link matches the desktop file's Exec
          ln -s $out/yandex_browser $out/bin/yandex-browser-stable

          # Clean up unnecessary dirs (optional, but good practice)
          # rm -rf opt usr etc cron.daily
        '';

        meta = with lib; {
          description = "Yandex Browser (Stable) - Custom Package";
          platforms = ["x86_64-linux"];
          sourceProvenance = with sourceTypes; [binaryNativeCode];
          license = licenses.unfree;
        };
      };
    in
      lib.mkAfter [
        yandex-browser-stable
        pkgs.passff-host # native messaging host for PassFF Firefox extension
      ];
  };
}
