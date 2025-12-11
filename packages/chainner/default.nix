{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  zstd,
  glib,
  gtk3,
  nss,
  nspr,
  dbus,
  atk,
  at-spi2-atk,
  at-spi2-core,
  pango,
  cairo,
  cups,
  xorg,
  libxkbcommon,
  expat,
  mesa,
  libdrm,
  alsa-lib,
  systemd,
}: let
  pname = "chainner";
  version = "0.25.1";

  src = fetchurl {
    url = "https://github.com/chaiNNer-org/chaiNNer/releases/download/v${version}/chaiNNer_${version}-x64-linux-debian.deb";
    hash = "sha256-6XqfdKlTRuLrPxpMzfYz4KT6U6r2A4VMUvUKCqnkNlg=";
  };

  runtimeLibs = [
    glib
    gtk3
    nss
    nspr
    dbus
    atk
    at-spi2-atk
    at-spi2-core
    pango
    cairo
    cups
    xorg.libX11
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXrandr
    xorg.libxcb
    libxkbcommon
    expat
    mesa
    libdrm
    alsa-lib
    systemd
  ];
in
  stdenvNoCC.mkDerivation {
    inherit pname version src;

    sourceRoot = ".";
    nativeBuildInputs = [autoPatchelfHook makeWrapper zstd];
    buildInputs = runtimeLibs;

    unpackPhase = ''
      runHook preUnpack
      ar p "$src" data.tar.zst | tar --use-compress-program=unzstd -x
      runHook postUnpack
    '';

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r usr/* "$out/"

      rm -f "$out/lib/chainner/chrome-sandbox"

      substituteInPlace "$out/share/applications/chainner.desktop" \
        --replace-fail "Exec=chainner %U" "Exec=$out/bin/chainner %U" \
        --replace-fail "Icon=chainner" "Icon=$out/share/pixmaps/chainner.png"

      wrapProgram "$out/bin/chainner" --add-flags "--no-sandbox"
      runHook postInstall
    '';

    meta = with lib; {
      description = "Flowchart-based image processing GUI";
      homepage = "https://github.com/chaiNNer-org/chaiNNer";
      changelog = "https://github.com/chaiNNer-org/chaiNNer/releases/tag/v${version}";
      license = licenses.gpl3Only;
      platforms = ["x86_64-linux"];
      mainProgram = "chainner";
      sourceProvenance = [sourceTypes.binaryNativeCode];
      maintainers = with maintainers; [];
    };
  }
