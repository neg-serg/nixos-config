{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
  glib,
  freetype,
  fontconfig,
  libx11,
  libxkbcommon,
  libglvnd,
  wayland,
  libpulseaudio,
  alsa-lib,
}:
let
  version = "6.9.3";
  pname = "telegram";

  src = fetchurl {
    url = "https://github.com/telegramdesktop/tdesktop/releases/download/v${version}/tsetup.${version}.tar.xz";
    hash = "sha256-Aplmm/HKzIB3uzTClYk/+qcC2qoR6l0wJtZ6vvbAa9Y=";
  };

  desktopItem = makeDesktopItem {
    name = "org.telegram.desktop";
    desktopName = "Telegram Desktop";
    exec = "telegram -- %u";
    icon = "telegram";
    terminal = false;
    type = "Application";
    categories = [ "Network" "InstantMessaging" "Chat" ];
    mimeTypes = [ "x-scheme-handler/tg" ];
    startupWMClass = "org.telegram.desktop";
  };
in
stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    copyDesktopItems
  ];

  # Only libraries the binary actually links against (from ldd)
  buildInputs = [
    glib # libgio-2.0, libglib-2.0, libgobject-2.0
    freetype
    fontconfig
    libx11
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/{bin,share/applications}

    # Install Telegram binary + Updater
    install -m755 Telegram $out/bin/telegram
    install -m755 Updater $out/bin/telegram-updater 2>/dev/null || true

    # Qt6 and bundled libs need these at runtime (dlopen'd, not linked)
    wrapProgram $out/bin/telegram \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [
        wayland
        libxkbcommon
        libglvnd
        libpulseaudio
        alsa-lib
      ]}

    runHook postInstall
  '';

  desktopItems = [ desktopItem ];

  meta = with lib; {
    description = "Telegram Desktop messaging app (official static binary, zero GTK deps)";
    homepage = "https://desktop.telegram.org";
    license = licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "telegram";
  };
}
