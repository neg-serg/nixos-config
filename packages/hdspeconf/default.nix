{
  lib,
  stdenv,
  fetchFromGitHub,
  alsa-lib,
  wxwidgets_3_2,
}:

stdenv.mkDerivation rec {
  pname = "hdspeconf";
  version = "unstable-2022-03-30";

  src = fetchFromGitHub {
    owner = "PhilippeBekaert";
    repo = "hdspeconf";
    rev = "764ad26f18947368b7c329c6f1c07fc95098158e";
    hash = "sha256-n3Qg6x51q5MvqONPiT4c2SOFg/zxwGNs45Mr7jxU2TA=";
  };

  nativeBuildInputs = [ wxwidgets_3_2 ];
  buildInputs = [ alsa-lib ];

  # Fix include path: Makefile uses -I.. but sources are in repo root
  postPatch = ''
    substituteInPlace Makefile \
      --replace-fail '-I..' '-I.'
  '';

  buildPhase = ''
    runHook preBuild
    make ${lib.optionalString stdenv.hostPlatform.isAarch64 "CXXFLAGS=-Wall -O2"}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp hdspeconf $out/bin/
    runHook postInstall
  '';

  meta = with lib; {
    description = "User space configuration tool for RME HDSPe cards (snd-hdspe driver)";
    homepage = "https://github.com/PhilippeBekaert/hdspeconf";
    license = licenses.gpl3;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
