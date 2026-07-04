{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  ffmpeg_7,
  libclang,
  clang,
}:

rustPlatform.buildRustPackage rec {
  pname = "palettum";
  version = "0.6.1";

  src = fetchFromGitHub {
    owner = "arrowpc";
    repo = "palettum";
    rev = "46a75935552925154d0da52625d5ce23a0f53e08";
    hash = "sha256-kUmulMce7PKVPWxtcWLf41TZ1KUPeo596E2NsLeAjO8=";
  };

  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "console-0.15.11" = "sha256-1e4XURp8GNG8OGBfz2dhXp4Fg5tydJ5yGHXCpR0JEZY=";
      "indicatif-0.17.11" = "sha256-K4exo6JnyNbpe1l+hFFzwylAorPFQ/xkQMj/0vHssk0=";
    };
  };

  nativeBuildInputs = [
    pkg-config
    clang
  ];

  buildInputs = [
    ffmpeg_7
  ];

  LIBCLANG_PATH = "${libclang.lib}/lib";
  BINDGEN_EXTRA_CLANG_ARGS = "-isystem ${lib.getDev ffmpeg_7}/include";

  cargoBuildFlags = [ "-p" "cli" ];

  meta = with lib; {
    description = "Web app and CLI tool that lets you recolor images, GIFs, and videos with any custom palette";
    homepage = "https://palettum.com";
    license = licenses.agpl3Only;
    mainProgram = "palettum";
    platforms = platforms.linux;
  };
}
