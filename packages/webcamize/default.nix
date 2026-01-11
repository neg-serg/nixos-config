{
  lib,
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  ffmpeg-full,
  gphoto2,
  v4l-utils,
  jq,
  pkg-config,
  libgphoto2,
  kmod,
}:
stdenv.mkDerivation rec {
  pname = "webcamize";
  version = "2.0.1";

  src = fetchFromGitHub {
    owner = "cowtoolz";
    repo = "webcamize";
    rev = "v${version}";
    hash = "sha256-rmATEcAcngCHidMFXNocrhP06LKNLEb+9jfFMGL4AKU=";
  };

  nativeBuildInputs = [
    makeWrapper
    pkg-config
  ];
  buildInputs = [
    libgphoto2
    ffmpeg-full
    kmod
  ];

  installPhase = ''
    mkdir -p $out/bin
    make bin/webcamize
    install -Dm755 bin/webcamize $out/bin/webcamize
    wrapProgram $out/bin/webcamize \
      --prefix PATH : ${
        lib.makeBinPath [
          ffmpeg-full
          gphoto2
          v4l-utils
          jq
        ]
      }
  '';

  meta = with lib; {
    description = "Use (almost) any camera as a webcam";
    homepage = "https://github.com/cowtoolz/webcamize";
    license = licenses.mit;
    platforms = platforms.linux;
    maintainers = [ ];
    mainProgram = "webcamize";
  };
}
