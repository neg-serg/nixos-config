# crabwalk

A miniature platformer drawn on the user's 32:9 waterfall wallpaper. The painting is not a backdrop:
it *is* the level. One world unit is one wallpaper pixel, the background is copied 1:1 with nearest
sampling, and the player character is the crab that already sits on the grass ledge in the picture.

`crabwalk` starts on the crab's own ledge, collects seven spray drops, dives through the lake and
climbs the boulder staircase to the spray ring at the foot of the waterfall.

## Running

```
nix run /etc/nixos#crabwalk
```

Or, with the package installed, plain `crabwalk`.

| Key                    | Action                                   |
| ---------------------- | ---------------------------------------- |
| `A` / `D`, `←` / `→`   | walk                                     |
| `Space`, `W`, `↑`, `Z` | jump; in water: leap out                 |
| `S`, `↓`               | dive (in water)                          |
| `R`                    | restart (on the win screen)              |
| `F11`                  | toggle fullscreen                        |
| `F12`                  | save a screenshot to `/tmp/crabwalk.ppm` |
| `Esc`                  | quit                                     |

The on-screen text is Russian because the game is for this machine's owner; code, comments and this
document stay English.

## How the painting becomes a level

- `assets/world.jpg` is the wallpaper at full resolution (7680x2160). The game window is 1920x1080
  world pixels scaled 2x, which is exactly the 3840x2160 panel; a standing-still frame shows the
  wallpaper crop without resampling.
- `assets/crab.png` is cut out of the painting by `tools/extract_crab.py`: the warm (red/orange)
  pixels inside the crab's bounding box, holes filled, grass leftovers removed. The claws in the
  game are the painting's claws.
- Platforms sit on the rock edges that are actually visible in the picture. `tools/measure_level.py`
  prints the top-of-rock profile used for the staircase (`1810..1836 / 1900 / 1984`); the plateau is
  at the grass fringe (`y = 1840`), the lake surface follows the painted shoreline through
  `Level::waterline`.
- The waterfall streaks and the lake highlights are generated at startup from the pixels: only
  bright bluish pixels inside the falls region become moving streaks, only blue pixels in the lake
  become shimmer. Nothing is drawn on dry land.
- The scene itself never moves. Water, spray, motes and the crab animate; the painting stays
  pixel-identical, which is what keeps the "wallpaper came alive" effect honest.

## Controls and feel

Coyote time (0.10 s), jump buffering (0.12 s), variable jump height, a swim state with buoyancy and
a dive key, and dust/splash particles. Physics constants live at the top of `src/player.rs`.

## Verification

Unit tests (no display needed):

```
cargo test
```

Render the wallpaper without any overlay and compare it with the source crop:

```
SDL_VIDEODRIVER=dummy cargo run -- --shot /tmp/clean.ppm --clean --cam 3600,1080
magick /tmp/clean.ppm /path/to/crop.png -metric RMSE compare: -
```

The remaining difference is JPEG-decoder rounding (max 4/255 per channel on this wallpaper), not
scaling or filtering: the texture is uploaded from the same decoded buffer and copied 1:1.

QA frames after tuning the level:

```
crabwalk --shot /tmp/falls.ppm --state play --time 3 --cam 250,1020 --debug
```
