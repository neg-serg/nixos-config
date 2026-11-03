# crabwalk — a miniature platformer painted on the waterfall wallpaper.
#
# One world unit is one wallpaper pixel; the background is the wallpaper at
# native resolution, the mascot is the crab already sitting on the ledge in
# the painting. Art is embedded with include_bytes!, so the package ships a
# single self-contained binary.
{
  lib,
  rustPlatform,
  pkg-config,
  SDL2,
}:

rustPlatform.buildRustPackage {
  pname = "catwalk";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ SDL2 ];

  # Physics, collision and the level geometry are pure Rust; the tests run
  # without a display.
  doCheck = true;

  meta = {
    description = "Tiny pixel-perfect cat platformer on the waterfall wallpaper";
    longDescription = ''
      A miniature platformer that uses the user's 7680x2160 waterfall
      wallpaper as its level: the painting is the world at 1:1, and a fan-made
      pixel-art ginger cat (drawn by tools/generate_cat.py) runs, spins and
      swims through it while the falls, lake and spray are
      animated with overlays derived from the same pixels. Collect seven spray
      drops, cross the lake and climb the boulders to the falls.
    '';
    homepage = "https://github.com/neg-serg/nixos-config";
    license = lib.licenses.mit;
    maintainers = [ ];
    platforms = lib.platforms.linux;
    mainProgram = "catwalk";
  };
}
