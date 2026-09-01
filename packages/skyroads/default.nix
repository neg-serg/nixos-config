{
  lib,
  stdenv,
  cmake,
  ninja,
  SDL2,
  fetchFromGitHub,
  fetchurl,
  unzip,
  makeWrapper,
}:
let
  # Freeware game data from Bluemoon's official site (the repo itself never
  # redistributes it). The game falls back to AdLib FM (Nuked-OPL3) without
  # the optional TimGM6mb.sf2 wavetable soundfont, which we skip.
  gameData = stdenv.mkDerivation {
    pname = "skyroads-data";
    version = "1993-04-24";
    src = fetchurl {
      url = "http://www.bluemoon.ee/history/skyroads/skyroads.zip";
      sha256 = "sha256-JHYv4UGWpkIiQoj+IGPJ0MADO+nFtLL5f97Qk5CAPuQ=";
    };
    nativeBuildInputs = [ unzip ];
    unpackPhase = ''
      mkdir -p data
      unzip -q "$src" -d data
    '';
    installPhase = ''
      mkdir -p "$out"
      cp -r data/. "$out/"
    '';
  };
in
stdenv.mkDerivation rec {
  pname = "skyroads";
  version = "0-unstable-2026-08-29";

  src = fetchFromGitHub {
    owner = "pedrocatalao";
    repo = "skyroads-sdl";
    rev = "c60aefd8625c2520d21aa90e0da9795fc1a8db58";
    hash = "sha256-UDLZ7vTZZeImhsIqoo1Thj/W3dER7qTols3441mMXIQ=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    makeWrapper
  ];

  buildInputs = [
    SDL2
  ];

  configurePhase = ''
    runHook preConfigure
    cmake -S . -B build
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    cmake --build build --target skyroads
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 build/skyroads "$out/libexec/skyroads"
    mkdir -p "$out/share/skyroads"
    cp -r ${gameData}/. "$out/share/skyroads/"
    makeWrapper "$out/libexec/skyroads" "$out/bin/skyroads" --add-flags "$out/share/skyroads"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Native SDL2 port of the classic DOS game SkyRoads (Bluemoon, 1993) — no DOSBox";
    homepage = "https://github.com/pedrocatalao/skyroads-sdl";
    # Port code is MIT; game content is Bluemoon's freeware, bundled as data.
    license = licenses.mit;
    mainProgram = "skyroads";
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
