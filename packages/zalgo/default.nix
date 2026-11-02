##
# Package: zalgo
# Purpose: `zalgo` — read text on stdin and print it back with combining marks
#   above/on/below every character (the "cursed text" effect). Port of
#   files/art/fun-art/zalgo.py (originally by MetroWind), keeping its flags.
#
# Rust, no crates: the mark sets are copied verbatim from the original and the
# random choice comes from a small in-crate generator.
{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "zalgo";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "Zalgo text generator (stdin to stdout)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "zalgo";
  };
}
