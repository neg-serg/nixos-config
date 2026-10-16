# Theme pipeline — wallpaper → `theme.plm` (PH1-T2)

One command turns the current wallpaper into `~/.config/pleamar/theme.plm`, the writable palette
half that scenes opt into. It mirrors the legacy Quickshell contract (`docs/INTERFACES.md` §1.4 and
§3.3): the frozen `lib/palette.plm` keeps the QS names and values, and `theme.plm` adds the
wallpaper's own tones under a `skin.` prefix — the QS wallpaper accent
(`Services/WallpaperAccent.qml` + `Helpers/AccentSampler.js` + `Settings/Theme.qml`'s
`accentPrimary`) and the greeter's Oklab k-means palette (`greeter/background/BackgroundImage.qml`),
without QML or PyQt anywhere.

Files in this directory:

| file                | what it is                                                                       |
| ------------------- | -------------------------------------------------------------------------------- |
| `theme.sh`          | the generator: resolves the wallpaper, writes `theme.plm` atomically             |
| `theme-extract.awk` | the two samplers (accent mean + Oklab k-means), a port of the legacy JS/QML      |
| `theme.default.plm` | the seed copy for a fresh session; `theme.sh` overwrites the live file, not it   |
| `test.sh`           | hermetic proof: temp HOME/XDG, fixtures, assertions, optional `--check` consumer |
| `README.md`         | this file                                                                        |

## The contract

`~/.config/pleamar/theme.plm` is **generated**, never edited by hand and never managed by Nix: a
module deploy that makes it read-only is a bug. A scene that wants the wallpaper look imports it
after the palette, as §1.4 fixes:

```plm
import "../../lib/palette.plm"
import "../../theme.plm"
```

Rules the file obeys, so PH2 writers can rely on them:

- it is `library Skin strict { … }`, strict and declarations only;
- it declares **only `skin.*` names** — the same names `lib/palette.plm` uses (`coal`, `surface`,
  `ink`, `accent`, …) are never re-declared, so no import changes what a palette name means;
- the names are the frozen set below; a scene reads them explicitly (`skin.accent`, `skin.ink`);
- the values are colours (`#rrggbb`); alpha is applied at the drawing site, exactly as with
  `lib/palette.plm`;
- pleamar re-reads an imported file when it changes, so **rewriting `theme.plm` re-themes every
  running scene that imports it** (no restart, no signal). A scene that needs a palette change
  without a file rewrite uses the §1.4 runtime route instead: `rgb(red, green, blue)` over three
  facts its own logic updates — see `~/src/Vitreus/palette-live.plm` for the pattern.

### The exported names

| name                | value                                             | from                                              |
| ------------------- | ------------------------------------------------- | ------------------------------------------------- |
| `skin.coal`         | darkest wallpaper tone (`colors.background` role) | darkest of four Oklab k-means clusters            |
| `skin.surface`      | raised surface (`colors.surfaceVariant` role)     | second-darkest cluster                            |
| `skin.ink`          | text (`colors.text.primary` role)                 | lightest cluster, readability-clamped (see below) |
| `skin.ink.dim`      | secondary text (`colors.text.secondary` role)     | `mix(skin.ink, skin.surface, 35%)`                |
| `skin.accent`       | accent (`colors.accent.primary` role)             | wallpaper mean hue, QS saturation/lightness       |
| `skin.accent.hover` | `Theme.accentHover`                               | `mix(skin.accent, #ffffff, 20%)`                  |
| `skin.accent.deep`  | `Theme.accentDarkStrong`                          | `mix(skin.accent, skin.coal, 80%)`                |
| `skin.on.accent`    | `colors.onAccent`                                 | constant `#ffffff`, as in the legacy theme        |

`theme.sh` writes one comment above each name saying where that name's value came from — the sampled
wallpaper, `--accent`, `--from-json`, or the QS base-palette fallback.

## The command

```sh
~/.config/pleamar/scripts/theme/theme.sh            # or wherever the module deploys it
# or, from the repo during development:
files/pleamar/scripts/theme/theme.sh
```

```
Usage: theme.sh [--wallpaper FILE] [--accent '#RRGGBB'] [--from-json FILE] [--help]

--wallpaper FILE   sample this image instead of the cache's current wallpaper
--accent '#RGB'    force the accent (wins over --from-json and the sampler)
--from-json FILE   read any of coal, surface, ink, accent from a JSON
                   object (string values); --accent wins over a key it gives
```

Wallpaper resolution order:

1. `--wallpaper FILE` (unreadable is an error);
1. `$XDG_CACHE_HOME/pleamar/wallpaper-path`, first line (`INTERFACES.md` §1.2 reserves the path for
   this pipeline);
1. `$XDG_CACHE_HOME/quickshell-wallpaper-path`, the legacy cache `WallpaperAccent.qml` watched —
   what the session publishes today.

The writer is a module, not this script: `wl-state-sync.service` / the wallpaper daemon must publish
`~/.cache/pleamar/wallpaper-path` (today only the legacy path is written; see the integration
section).

Behaviour:

- **atomic**: a `mktemp` file in `~/.config/pleamar`, then `mv -f`; a reader never sees a half file;
- **narrow**: `mkdir -p ~/.config/pleamar` and that one file — nothing else under it is touched;
- **honest about missing input**: no wallpaper and no `--accent`/`--from-json` is an error on
  stderr, exit 1, and the previous `theme.plm` (if any) is left untouched; a cache path whose file
  is gone is reported and only tolerated when an explicit colour was given;
- exits `0` written, `1` nothing to write or a bad input, `2` usage or a missing tool.

Environment overrides: `MAGICK_BIN` (default `magick`), `AWK_BIN` (default `awk`), `JQ_BIN` (default
`jq`, needed only for `--from-json`). Dependencies: bash, ImageMagick 7, a POSIX awk, coreutils, jq
(for `--from-json`) — **no QML, no PyQt, no Python**.

## What is generated

Header, then the library (a real file from the test run):

```plm
library Skin strict {
    // colors.background role: the wallpaper's darkest Oklab k-means cluster.
    let skin.coal = #061c38
    // colors.surfaceVariant role: the wallpaper's second-darkest cluster.
    let skin.surface = #023663
    // colors.text.primary role: the lightest cluster, pushed to 4.5:1 contrast on skin.surface.
    let skin.ink = #66a6d7
    // colors.text.secondary role: skin.ink mixed 35% toward skin.surface.
    let skin.ink.dim = mix(skin.ink, skin.surface, 35%)
    // colors.accent.primary role: … hue-matched onto #006FCC (Settings/Theme.qml accentPrimary).
    let skin.accent = #0067cc
    let skin.accent.hover = mix(skin.accent, #ffffff, 20%)
    let skin.accent.deep = mix(skin.accent, skin.coal, 80%)
    let skin.on.accent = #ffffff
}
```

`theme.default.plm` holds the same names with the QS base-palette values; the module copies it once
to the live path so scenes compile before the first wallpaper change.

## QS token → `skin.*` mapping

The full palette translation is `INTERFACES.md` §3.3; this is the wallpaper half of it.

| QS token / derived token (legacy) | `skin.*`            | how the generator gets it                                                                           |
| --------------------------------- | ------------------- | --------------------------------------------------------------------------------------------------- |
| `colors.background` `#ff000000`   | `skin.coal`         | greeter k-means cluster 1/4 (darkest), chroma ×1.35                                                 |
| `colors.surfaceVariant` `#242A35` | `skin.surface`      | cluster 2/4                                                                                         |
| `colors.text.primary` `#CBD6E5`   | `skin.ink`          | cluster 4/4, then pushed toward white (or black on a light palette) to WCAG 4.5:1 on `skin.surface` |
| `colors.text.secondary` `#AEB9C8` | `skin.ink.dim`      | `mix(ink, surface, 35%)` (the QS step below primary)                                                |
| `colors.accent.primary` `#006FCC` | `skin.accent`       | `AccentSampler` mean hue; HSL saturation/lightness of `#006FCC`                                     |
| `Theme.accentHover`               | `skin.accent.hover` | `mix(accent, #ffffff, 20%)` — the same formula                                                      |
| `Theme.accentDarkStrong`          | `skin.accent.deep`  | `mix(accent, coal, 80%)` — the same formula                                                         |
| `colors.onAccent` `#FFFFFF`       | `skin.on.accent`    | constant, as in `Settings/Theme.qml`                                                                |

The mappings `Theme.surfaceHover`, `surfaceActive`, `borderSubtle`, `overlayWeak/Strong` (alpha
numbers in `lib/palette.plm`) stay scene-side: `skin.*` carries tones, the drawing site applies
`ink.hover`/`veil`-style alphas from the frozen palette.

### How the samplers mirror the legacy code, and the deviations

- **Tones** — `theme-extract.awk` ports `BackgroundImage.qml`'s `paintPalette()`: Oklab, k=4, pixel
  weight `0.25 + saturation × 1.75`, seeds spread over the lightness range, 16 iterations, centres
  sorted darkest to lightest, chroma ×1.35 (`greeter.posterizeChroma`).
- **Accent** — ports `AccentSampler.sampleAccent()`: the mean of pixels with chroma ≥ 10 and mean
  brightness 20..235, then the relaxed pass (≥ 8, 20..240), then every pixel; the mean is
  hue-matched the way `Color.matchHue(mean, "#006FCC")` does for `Theme.accentPrimary` (wallpaper
  hue, reference saturation 1.0 / lightness 0.4).
- **Sample** — one ImageMagick 48×48 grid feeds both samplers. The accent grid in `Bar.qml` is
  48×48; the greeter's k-means ran on 32×32 — the same algorithm on a finer grid.
- **Hue-less source** — when the mean has no chroma, the accent stays `#006FCC`. `matchHue()` would
  take hue 0 from the grey and paint a grey wallpaper's accent red; that legacy bug is deliberately
  not ported.
- **Readability clamp** — `skin.ink` is pushed from the lightest (or, on a light palette, darkest)
  centre toward white (black) until it contrasts with `skin.surface` at 4.5:1, or reaches the
  extreme. QS used a fixed `text.primary`; a wallpaper-derived text tone needs its own floor.
- **Secondary text** — `skin.ink.dim` is always the `mix(skin.ink, skin.surface, 35%)` expression,
  so it follows whatever `ink`/`surface` the run produced (including `--from-json` overrides). QS's
  flat `colors.text.secondary` `#AEB9C8` is not copied: a fixed grey would not follow the wallpaper.
- The samplers are numeric ports, not the pixel-exact originals: the sample is a resample of the
  image and the mean/grid rounding differs from Qt's.

## Tests

`test.sh` is hermetic: it draws its own fixtures with ImageMagick into a fresh `mktemp -d`, and
never reads or writes the real `~/.config`. It asserts the legacy-cache and `pleamar/wallpaper-path`
resolution (including precedence), the golden palette of a fixture, the readability clamp on a light
fixture, `--accent` and `--from-json` overrides, the fallback values, the missing-input error with
no file written, the atomic write (a failed run leaves the previous file and no temp behind), and
`theme.default.plm` agreeing with the script's fallbacks. With the compiler available it also writes
a `/tmp` consumer scene (a capsule plus text and accent bars built from `skin.*`, scale through
`group { scale: ui }` per D9), imports the generated `theme.plm` next to `lib/palette.plm`, and runs
`pleamar --check` on it:

```sh
PLEAMAR_BIN=/path/to/pleamar files/pleamar/scripts/theme/test.sh
# ok: …
# ok: consumer with the generated theme.plm compiles:
#   /tmp/…/theme_proof.plm: ok · 9 properties, 17 instructions, 0 layers, …
# theme-test: all checks passed
```

Without a binary on `PATH` the consumer steps are a skip notice, not a failure. `test.sh` does not
render (no `pleamar-wm` headless here): `--check` proves the file compiles, and the harness'
`smoke.sh` owns the PNGs. The live-restyle claim is the compiler's documented hot reload of an
imported file, not a claim proved by a screenshot in this task.

## What the Nix module must deploy, and what must call the script

The module task owns this (PH1-T2 does not edit `modules/`); the requirements are:

1. **The writable path.** `~/.config/pleamar/` must be a real, user-writable directory whose `lib/`
   and `shells/` are links into the repo — not one link of the whole directory. Nix must never own
   `theme.plm`: the script rewrites it, and the module's activation must not replace it.

1. **A seed.** Copy `scripts/theme/theme.default.plm` to `~/.config/pleamar/theme.plm` **only when
   it does not exist**, so the scenes that import `../../theme.plm` compile on a fresh login.

1. **The script.** Deploy `theme.sh` *with* `theme-extract.awk` in the same directory (the script
   finds its sibling and resolves symlinks, so a link to the directory is fine). A store wrapper
   (`writeShellApplication` style) works if both files sit next to each other; put `imagemagick`,
   `gawk`, `jq` and `coreutils` on its `PATH`, or point `MAGICK_BIN`/`AWK_BIN`/`JQ_BIN` at the store
   paths.

1. **The trigger.** Something must run the script whenever the wallpaper changes. Today
   `wl-state-sync.service` already runs on every change and publishes
   `~/.cache/quickshell-wallpaper-path`; the smallest correct step is an `ExecStartPost` on that
   unit (or a path unit watching the same file). The README of this pipeline recommends moving the
   publish to `~/.cache/pleamar/wallpaper-path` (§1.2 reserves it) and wiring:

   ```nix
   systemd.user.services."pleamar-theme" = {
     description = "Write ~/.config/pleamar/theme.plm from the wallpaper";
     partOf = [ "graphical-session.target" ];
     wantedBy = [ "graphical-session.target" ];
     serviceConfig.Type = "oneshot";
     serviceConfig.ExecStart = "${pleamarTheme}";      # theme.sh + awk + its PATH
     unitConfig.StartLimitIntervalSec = 0;             # changes arrive in bursts
   };
   systemd.user.paths."pleamar-theme" = {
     wantedBy = [ "graphical-session.target" ];
     pathConfig = {
       PathChanged = "%h/.cache/pleamar/wallpaper-path";
       Unit = "pleamar-theme.service";
     };
   };
   ```

   Until the cutover, watch `%h/.cache/quickshell-wallpaper-path` as well (or keep the
   `ExecStartPost`), so both sessions keep working.

No `theme` scene was written: nothing about the pipeline needs a pleamar surface. The watcher is a
systemd unit (module-side), and a scene that wants live tint without a file rewrite uses `rgb()`
facts as §1.4 describes.
