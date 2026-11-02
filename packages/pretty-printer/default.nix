##
# Package: pretty-printer
# Purpose: The coloured bracket/glyph output used by the personal CLI tools —
#   `ppinfo` (file size and line count per path) and `vid-info` (one line per
#   video file from ffprobe).
#
# Rust, no crates: the escape chains are the ones the `colored` package emits
# (`fg(n)` = ESC[38;5;<n>m, only when stdout is a terminal and `NO_COLOR` is
# unset), and the tests pin them against strings captured from the Python
# implementation this replaces. `wc` and `ffprobe` stay external programs.
{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "pretty-printer";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "Pretty-printing helpers: coloured file info (ppinfo) and video info (vid-info)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.unlicense;
    mainProgram = "ppinfo";
  };
}
