##
# Package: blizzard
# Purpose: `blizzard` — animated black-metal blizzard WebP generator built from
#   a reference image. Rust port of files/fastfetch/make_blizzard.py with the
#   same CLI, palettes and dithering kernels.
#
# Dependencies: `image` (zune-jpeg) decodes the reference JPEG and `webp`
#   wraps libwebp's WebPAnimEncoder for the animated output. libwebp-sys 0.9
#   vendors libwebp and builds it with cc, so no system libwebp is needed —
#   only the C compiler and Rust toolchain from stdenv/rustPlatform.
{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "blizzard";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "Black-metal blizzard animated WebP generator";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "blizzard";
  };
}
