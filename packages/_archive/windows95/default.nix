{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
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
  mesa,
  libxkbcommon,
  expat,
  alsa-lib,
  systemd,
  libdrm,
}:
let
  pname = "windows95";
  version = "4.0.0";

  src = fetchurl {
    url = "https://github.com/felixrieseberg/windows95/releases/download/v${version}/windows95_${version}_amd64.deb";
    hash = "sha256-mbAWX2UneJIz6b0xJpBZW/qjLgtWYO7ZIyLiTO1Ib4M=";
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

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = runtimeLibs;

  sourceRoot = ".";

  unpackPhase = ''
    runHook preUnpack
    ar p "$src" data.tar.xz | tar -xJ
    runHook postUnpack
  '';

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r usr/* "$out/"

    rm -f "$out/lib/windows95/chrome-sandbox"

    substituteInPlace "$out/share/applications/windows95.desktop" \
      --replace-fail "Exec=windows95 %U" "Exec=$out/bin/windows95 %U" \
      --replace-fail "Icon=windows95" "Icon=$out/share/pixmaps/windows95.png"

    wrapProgram "$out/bin/windows95" \
      --add-flags "--no-sandbox"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Electron app bundling Windows 95 (v86-based)";
    homepage = "https://github.com/felixrieseberg/windows95";
    changelog = "https://github.com/felixrieseberg/windows95/releases/tag/v${version}";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "windows95";
    sourceProvenance = [ sourceTypes.binaryNativeCode ];
    maintainers = with maintainers; [ ];
  };
}
