{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  pipewire,
  alsa-lib,
  libclang,
  clang,
}:

rustPlatform.buildRustPackage rec {
  pname = "wiremix";
  version = "0.1.0-unstable-2025-01-28";

  src = fetchFromGitHub {
    owner = "tsowell";
    repo = "wiremix";
    rev = "master";
      sha256 = "sha256-DnRK/v4gBz99ngrKWGbn4saLQVDlBymQI8QIMGaUvNA=";
  };

  cargoHash = ""; # will be recalculated

  nativeBuildInputs = [
    pkg-config
    clang
  ];

  buildInputs = [
    pipewire
    alsa-lib
  ];

  LIBCLANG_PATH = "${libclang.lib}/lib";
  BINDGEN_EXTRA_CLANG_ARGS = "-isystem ${lib.getDev stdenv.cc.libc}/include";

  meta = with lib; {
    description = "PipeWire mixer for the terminal";
    homepage = "https://github.com/tsowell/wiremix";
    license = with licenses; [
      mit
      asl20
    ];
    mainProgram = "wiremix";
    platforms = platforms.linux;
  };
}
