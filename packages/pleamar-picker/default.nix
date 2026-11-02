##
# Package: pleamar-picker
# Purpose: the picker scene's commands: `pleamar-wallpaper-still` (a still for a
#   wallpaper, video frames included), `pleamar-wallpaper-apply` (everything a
#   new wallpaper sets: cache paths, the wallpaper command, matugen) and
#   `pleamar-picker` (the deck's toggle/open/close/reload/current CLI). Rust
#   ports of the former shell helpers; the external tools (ffmpeg, matugen,
#   wallpaper command, pleamar, systemctl, sleep) stay as they were.
{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "pleamar-picker";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  # Hermetic: fake tools, temporary HOME/XDG/TMPDIR, no real session.
  doCheck = true;

  meta = lib.mkMeta {
    description = "pleamar picker commands (wallpaper still/apply and the deck CLI)";
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.gpl3Plus;
    mainProgram = "pleamar-picker";
  };
}
