{
  description = "flake for blissify-rs (Rust CLI)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          # Use clang-based stdenv for better C++ compatibility
          config = {
            allowUnfree = true;
            permittedInsecurePackages = [ ];
          };
        };

        stdenv = pkgs.clangStdenv; # The default build environment for Unix packages in Nixpkgs
        clang = pkgs.llvmPackages.clang-unwrapped;

        blissify-rs-src = pkgs.fetchgit {
          url = "https://github.com/Polochon-street/blissify-rs.git";
          rev = "a0ad533d252f0a7d741496f5fbeec2f38862f795";
          sha256 = "sha256-QYm/vSMhS8sdAcN60FBbjvdiNlvf0Tmj4t1OtpsglcI=";
        };

        blissify-rs = pkgs.rustPlatform.buildRustPackage.override { inherit stdenv; } {
          name = "blissify-rs";
          pname = "blissify-rs";
          src = blissify-rs-src;

          nativeBuildInputs = [
            pkgs.pkg-config # discover C libraries/flags
            pkgs.cmake # build helper for C deps
          ];

          buildInputs = [
            pkgs.ffmpeg # audio decoding
            pkgs.ffmpeg.dev # headers for bindgen
            pkgs.llvmPackages.libclang # headers for bindgen
            pkgs.stdenv.cc.cc.lib # libstdc++ (or platform libc++)
            pkgs.sqlite # embedded DB
            pkgs.libcxx # libc++ runtime
          ];

          # Explicitly set all required header paths
          env = {
            LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";
            C_INCLUDE_PATH = "${pkgs.stdenv.cc.libc.dev}/include:${clang}/lib/clang/${clang.version}/include";
            BINDGEN_EXTRA_CLANG_ARGS = builtins.concatStringsSep " " [
              "-isystem ${pkgs.stdenv.cc.cc}/include"
              "-isystem ${pkgs.stdenv.cc.libc.dev}/include"
              "-isystem ${clang}/lib/clang/${clang.version}/include"
              "-isystem ${pkgs.ffmpeg.dev}/include" # Complete, cross-platform solution to record, convert and ...
            ];
            PKG_CONFIG_PATH = builtins.concatStringsSep ":" (
              map (drv: "${drv}/lib/pkgconfig") [
                pkgs.ffmpeg # Complete, cross-platform solution to record, convert and ...
                pkgs.ffmpeg.dev # Complete, cross-platform solution to record, convert and ...
              ]
            );
            FFMPEG_DIR = "${pkgs.ffmpeg.dev}"; # Complete, cross-platform solution to record, convert and ...
          };

          cargoLock = {
            lockFile = "${blissify-rs-src}/Cargo.lock";
          };

          meta = {
            description = "Automatic playlist generator written in Rust";
            homepage = "https://github.com/Polochon-street/blissify-rs";
            license = pkgs.lib.licenses.mit;
          };
        };
      in
      {
        packages = {
          default = blissify-rs;
          inherit blissify-rs;
          inherit blissify-rs-src;
        };

        devShells.default = pkgs.mkShell.override { inherit stdenv; } {
          nativeBuildInputs = [
            pkgs.pkg-config # discover C libraries/flags
            pkgs.cmake # build helper for C deps
          ];

          buildInputs = [
            pkgs.rustc # Rust compiler
            pkgs.cargo # package manager/build tool
            pkgs.rust-analyzer # IDE language server
            pkgs.ffmpeg # audio decoding
            pkgs.stdenv.cc.cc.lib # libstdc++
            pkgs.stdenv.cc.libc.dev # libc headers
            pkgs.llvmPackages.libclang # headers for bindgen
            pkgs.sqlite # database client/libs
            clang # C/CPP compiler (local let var)
            pkgs.libcxx # libc++ runtime
          ];

          shellHook = ''
            export LIBCLANG_PATH=${pkgs.llvmPackages.libclang.lib}/lib
            export C_INCLUDE_PATH="${pkgs.stdenv.cc.libc.dev}/include:${clang}/lib/clang/${clang.version}/include"
            export BINDGEN_EXTRA_CLANG_ARGS="\
              -isystem ${pkgs.stdenv.cc.cc}/include \
              -isystem ${pkgs.stdenv.cc.libc.dev}/include \
              -isystem ${clang}/lib/clang/${clang.version}/include \
              -isystem ${pkgs.ffmpeg.dev}/include" # Complete, cross-platform solution to record, convert and ...
            export PKG_CONFIG_PATH="$(printf '%s:%s' ${pkgs.ffmpeg}/lib/pkgconfig ${pkgs.ffmpeg.dev}/lib/pkgconfig)" # Complete, cross-platform solution to record, convert and ...
            export FFMPEG_DIR=${pkgs.ffmpeg.dev} # Complete, cross-platform solution to record, convert and ...

            echo
            echo "✅ Rust devShell for blissify-rs ready."
            echo
          '';
        };
      }
    );
}
