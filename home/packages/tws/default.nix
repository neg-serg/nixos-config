{
  # ref: https://git.sr.ht/~rhizomic/tws
  lib,
  fetchurl,
  stdenv,
  gnused,
  gnutar,
  patchelf,
  makeFontsCache,
  bash,
  alsa-lib,
  at-spi2-atk,
  cairo,
  cups,
  dbus,
  expat,
  ffmpeg,
  fontconfig,
  freetype,
  gdk-pixbuf,
  glib,
  gtk2,
  gtk3,
  javaPackages,
  libdrm,
  libGL,
  libxkbcommon,
  mesa,
  nspr,
  nss,
  pango,
  xorg,
  zlib,
}: let
  libPath = lib.makeLibraryPath [
    alsa-lib
    at-spi2-atk
    cairo
    cups
    dbus
    expat
    ffmpeg
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk2
    gtk3
    javaPackages.openjfx21
    libdrm
    libGL
    libxkbcommon
    mesa
    nspr
    nss
    pango
    xorg.libXfixes
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXext
    xorg.libXrandr
    xorg.libXrender
    xorg.libXtst
    xorg.libXi
    xorg.libXxf86vm
    xorg.libxcb
    xorg.libX11
    zlib
  ];
in
  stdenv.mkDerivation {
    pname = "ibkr-tws";
    version = "0";

    src = fetchurl {
      url = "https://download2.interactivebrokers.com/installers/tws/latest-standalone/tws-latest-standalone-linux-x64.sh";
      hash = "sha256-Wk7lRE5ypJeAQfvi5aEDZYfUF6fJ3ktueYYytHohIGU=";
    };

    nativeBuildInputs = [
      gnused
      gnutar
      patchelf
    ];

    unpackPhase = ''
      tws_length=$(stat -c %s "$src")
      sfx_length=$(sed -nE 's/^tail -c ([0-9]+).*/\1/p' "$src")

      mkdir install4j
      tail --bytes $sfx_length "$src" > sfx_archive.tar.gz
      tar -xf sfx_archive.tar.gz -C install4j 2> /dev/null

      mkdir jre
      tar -xf install4j/jre.tar.gz -C jre

      zero_dat_length=$(sed -nE 's/^file\.size\.0=([0-9]+)/\1/p' install4j/stats.properties)
      installer_length=$(($tws_length - $sfx_length - $zero_dat_length))

      head --bytes $installer_length "$src" > install.sh
      # || true masks broken pipe
      (tail --bytes +$(($installer_length + 1)) "$src" 2> /dev/null || true) | head --bytes $zero_dat_length > install4j/0.dat

      echo $tws_length : $sfx_length : $zero_dat_length : $installer_length
      stat install4j/0.dat
    '';

    buildPhase = ''
      for file in jre/bin/*; do
        patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" "$file"
      done

      unpack () {
        jar="`echo "$1" | awk '{ print substr($0,1,length($0)-5) }'`"
        jre/bin/unpack200 -r "$1" "$jar"
        chmod a+r "$jar"
      }

      for jarpack in jre/lib/*.jar.pack; do
        unpack $jarpack
      done

      for jarpack in jre/lib/ext/*.jar.pack; do
        unpack $jarpack
      done
    '';

    installPhase = ''
      install4j_installer=$(sed -nE 's/.*$INSTALL4J_JAVA_PREFIX.*install4j\.Installer([0-9]+).*/\1/p' "$src" | head -n 1)

      (cd install4j && \
        LD_LIBRARY_PATH='${libPath}:$LD_LIBRARY_PATH' \
        FONTCONFIG_FILE='${makeFontsCache {fontDirectories = [];}}' \
        INSTALL4J_JAVA_HOME='../jre' \
        ../jre/bin/java \
          -DjtsConfigDir='/home/jts' \
          -classpath 'i4jruntime.jar:launcher0.jar' \
          "install4j.Installer$install4j_installer" '-q' '-dir' "$out")

      mv jre "$out/jre"

      mkdir "$out/bin"
      cat <<EOF > "$out/bin/tws"
      #! ${lib.getExe bash}

      TWS_DIR="$XDG_DATA_HOME/tws"
      if [ ! -d "$TWS_DIR" ]; then
        mkdir -p "$TWS_DIR"
      fi

      LD_LIBRARY_PATH="${libPath}:$LD_LIBRARY_PATH" \
      INSTALL4J_JAVA_HOME="$out/jre" \
      $out/tws -J-DjtsConfigDir="$TWS_DIR"
      EOF

      mkdir -p "$out/share/icons/hicolor/128x128/apps"
      mv "$out/.install4j/tws.png" "$out/share/icons/hicolor/128x128/apps/tws.png"

      mkdir -p "$out/share/applications"
      cat <<EOF > "$out/share/applications/tws.desktop"
      [Desktop Entry]
      Type=Application
      Name=Trader Workstation
      Exec="$out/bin/tws"
      Icon=tws
      Categories=Office;Finance;
      StartupWMClass=install4j-jclient-LoginFrame
      EOF

      chmod +x "$out/bin/tws"
    '';

    meta = with lib; {
      description = "Interactive Brokers Trader Workstation (standalone installer)";
      homepage = "https://www.interactivebrokers.com";
      license = licenses.unfreeRedistributable;
      maintainers = with maintainers; [];
      platforms = ["x86_64-linux"];
      mainProgram = "tws";
    };
  }
