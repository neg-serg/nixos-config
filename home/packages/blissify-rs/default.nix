{
  lib,
  rustPlatform,
  clangStdenv,
  llvmPackages,
  pkg-config,
  cmake,
  ffmpeg,
  sqlite,
  libcxx,
  stdenv,
}: let
  rev = "a0ad533d252f0a7d741496f5fbeec2f38862f795";
  stdenv' = clangStdenv;
  clang = llvmPackages.clang-unwrapped;
  src = builtins.fetchTarball {
    url = "https://github.com/Polochon-street/blissify-rs/archive/${rev}.tar.gz";
    sha256 = "sha256-QYm/vSMhS8sdAcN60FBbjvdiNlvf0Tmj4t1OtpsglcI=";
  };
  version = "unstable-${lib.substring 0 7 rev}";
  builder = rustPlatform.buildRustPackage.override {stdenv = stdenv';};
in
  builder {
    pname = "blissify-rs";
    inherit version src;

    nativeBuildInputs = [
      pkg-config
      cmake
    ];

    buildInputs = [
      ffmpeg
      llvmPackages.libclang
      stdenv.cc.cc.lib
      sqlite
      libcxx
    ];

    env = {
      LIBCLANG_PATH = "${llvmPackages.libclang.lib}/lib";
      C_INCLUDE_PATH = "${stdenv.cc.libc.dev}/include:${clang}/lib/clang/${clang.version}/include";
      BINDGEN_EXTRA_CLANG_ARGS = lib.concatStringsSep " " [
        "-isystem ${stdenv.cc}/include"
        "-isystem ${stdenv.cc.libc.dev}/include"
        "-isystem ${clang}/lib/clang/${clang.version}/include"
      ];
    };

    cargoLock = {
      lockFile = "${src}/Cargo.lock";
    };

    meta = with lib; {
      description = "Automatic playlist generator written in Rust";
      homepage = "https://github.com/Polochon-street/blissify-rs";
      license = licenses.mit;
      platforms = platforms.linux;
      mainProgram = "blissify";
    };
  }
