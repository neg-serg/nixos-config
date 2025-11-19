{
  lib,
  stdenv,
  fetchFromGitHub,
}:
stdenv.mkDerivation rec {
  pname = "cxxmatrix";
  version = "unstable-2024-06-17";

  src = fetchFromGitHub {
    owner = "akinomyoga";
    repo = "cxxmatrix";
    rev = "c8d4ecfb8b6c22bb93f3e10a9d203209ba193591";
    hash = "sha256-5f0frZc5okqBhSU5wuv33DflvK9enBjmTSaUviaAFGo=";
  };

  installPhase = ''
    install -D cxxmatrix -t $out/bin/
  '';

  meta = with lib; {
    description = "C++ Matrix: The Matrix Reloaded in Terminals (Number falls, Banners, Matrix rains, Conway's Game of Life and Mandelbrot set";
    homepage = "https://github.com/akinomyoga/cxxmatrix";
    license = licenses.mit;
    mainProgram = "cxxmatrix";
    platforms = platforms.all;
  };
}
