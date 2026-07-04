{
  lib,
  buildGoModule,
  fetchFromGitHub,
  alsa-lib,
  pkg-config,
}:
buildGoModule rec {
  pname = "waves";
  version = "0.1.46";

  src = fetchFromGitHub {
    owner = "llehouerou";
    repo = "waves";
    rev = "v${version}";
    hash = "sha256-vl9xMUo6vaJfGAc5Cj1+bLPFYOVvZt+ZB0lkD+i8dtI=";
  };

  vendorHash = "sha256-lps0OdY8KoILJh/roY78iC+bYHPeENioQoIsL6v/N0A=";

  buildInputs = [
    alsa-lib
  ];

  nativeBuildInputs = [
    pkg-config
  ];

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${version}"
  ];

  meta = with lib; {
    description = "Keyboard-driven terminal music player with Soulseek downloads and Last.fm integration";
    homepage = "https://github.com/llehouerou/waves";
    license = licenses.gpl3Only;
    mainProgram = "waves";
    platforms = platforms.unix;
  };
}
