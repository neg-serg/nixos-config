{ lib
, stdenv
, rustPlatform
, fetchFromGitHub
, cmake
, pkg-config
, clang
, pipewire
, qt6
, gtk3
, lilv
, lv2
, serd
, suil
, libx11
, dbus
}:

rustPlatform.buildRustPackage rec {
  pname = "zestbay";
  version = "0.8.4";

  src = fetchFromGitHub {
    owner = "lemonxah";
    repo = "zestbay";
    rev = "v${version}";
    hash = "sha256-+G4OJUatQ9KSUstU62XlCV2GbFF4ciwv+V/JhFHSfpY=";
  };

  cargoHash = "sha256-yGtpOOrfY+7NybFZic7Q6z5yjaCvCF7ATOgfipRED/k=";

  nativeBuildInputs = [
    cmake
    pkg-config
    clang
    qt6.qtbase
    qt6.qtdeclarative
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    pipewire
    gtk3
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtwayland
    lilv
    lv2
    serd
    suil
    libx11
    dbus
  ];

  # Install .desktop file for app launcher visibility
  postInstall = ''
    install -Dm644 ${./zestbay.desktop} $out/share/applications/zestbay.desktop
  '';

  # CXX-Qt needs to find Qt6 via pkg-config at build time
  QT_SELECT = "6";

  # bindgen needs libclang.so for pipewire-sys and libspa-sys
  LIBCLANG_PATH = "${clang.cc.lib}/lib";

  # CXX-Qt's qt-build-utils v0.8.1 uses qmake/QMAKE to find tools like
  # qmlcachegen. In nixpkgs's split Qt6, qmake from qtbase only knows
  # about qtbase paths, but qmlcachegen lives in qtdeclarative/libexec.
  # Create a wrapper that overrides QT_INSTALL_LIBEXECS to point there.
  preBuild = ''
    qmakeWrapper="$PWD/qmake-wrapper"
    cat > "$qmakeWrapper" << 'WRAPPER'
    #!${stdenv.shell}
    for arg; do
      case "$arg" in
        QT_INSTALL_LIBEXECS) echo ${qt6.qtdeclarative}/libexec; exit 0;;
      esac
    done
    exec ${qt6.qtbase}/bin/qmake "$@"
    WRAPPER
    chmod +x "$qmakeWrapper"
    export QMAKE="$qmakeWrapper"
  '';

  meta = with lib; {
    description = "PipeWire patchbay with LV2/VST3/CLAP plugin hosting and auto-connect rules";
    longDescription = ''
      A PipeWire patchbay and audio routing manager with integrated LV2, VST3,
      and CLAP plugin hosting. Built with Rust + Qt6/QML for a fast, native
      Linux desktop experience.
    '';
    homepage = "https://github.com/lemonxah/zestbay";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "zestbay";
    platforms = platforms.linux;
  };
}
