{ lib
, rustPlatform
, fetchFromGitHub
, cmake
, pkg-config
, clang
, pipewire
, qt6
, lilv
, lv2
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

  cargoHash = lib.fakeHash;

  nativeBuildInputs = [
    cmake
    pkg-config
    clang
    qt6.qtbase
    qt6.qtdeclarative
  ];

  buildInputs = [
    pipewire
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtwayland
    lilv
    lv2
    suil
    libx11
    dbus
  ];

  # CXX-Qt needs to find Qt6 via pkg-config at build time
  QT_SELECT = "6";

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
