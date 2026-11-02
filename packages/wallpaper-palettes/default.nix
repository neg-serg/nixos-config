##
# Package: wallpaper-palettes
# Purpose: The colour scheme matugen would make from each wallpaper, streamed as
#   JSON lines for the cards of the pleamar picker scene
#   (`pleamar-wallpaper-palettes`). matugen runs as a dry run, so a card shows
#   the exact scheme its wallpaper will give; videos are read from a frame
#   grabbed by the still helper beside the binary.
#
# Rust, no crates: image dimensions come from the file headers (PNG/GIF/WEBP/
# JPEG), matugen and the still helper stay external programs.
{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "wallpaper-palettes";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = lib.mkMeta {
    description = "Colour schemes matugen would make from each wallpaper";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.gpl3Plus;
    mainProgram = "wallpaper-palettes";
  };
}
