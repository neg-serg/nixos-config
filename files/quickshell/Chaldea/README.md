# Chaldea widget exports

Vendored native QML exports from the [Chaldea](https://github.com/Aleph1-9012/Chaldea) widget
library (live catalogue at [chaldea.vercel.app](https://chaldea.vercel.app)), kept inside the shell
config so the designs can be tried and imported without the web generator.

## Provenance

- Upstream: `Aleph1-9012/Chaldea`, revision `8b088b47bf7927b7c029d501eacecff4c53b7b32` (2026-10-12),
  all 38 published widgets.
- Generated 2026-10-16 with the upstream CLI at default settings: `make content` in the repository
  root (Rust packager), then `bun run export <widget-id> <output-dir>` inside `frontend/`.
- Baseline: Quickshell 0.3.0 / Qt 6.11.2 (this host runs Quickshell 0.3.1).
- The exported files are kept byte-identical to upstream; edit a copy, not these files, and
  re-export instead of patching the tree when a design changes.

## Licence

Widget code and original widget assets are 0BSD: `LICENSE` sits in every widget folder and at the
top of this tree. The upstream application (site, packager, generator) is Apache-2.0 and is not
vendored here. Third-party material keeps its own terms (upstream `docs/licensing.md`); the
lockscreen wallpapers ship exactly as exported.

## Try a widget

Every folder is self-contained: `Widget.qml` plus its helper QML/JS files, a `shell.qml` launcher
and upstream notes. Run the launcher in a normal window:

```sh
qs -p ~/.config/quickshell/Chaldea/player/matrix/shell.qml
```

## Use a widget in the shell

Import the folder by relative path and instantiate its `Widget`:

```qml
import "../Chaldea/player/matrix" as Matrix

Matrix.Widget {
    width: 420
}
```

The path is relative to the importing file. Customization properties sit at the top of each
`Widget.qml`; per-design settings, controls and integration hooks are documented in that folder's
`README.md`.

## Behaviour notes

- Quick notes hold their notes in memory only - there is no disk storage. A host can listen to
  `notesEdited()` and read `snapshot()`.
- Player exports use MPRIS in the native QML; the browser previews do not.
- Lockscreen exports are visual components and demo interactions only: they do not authenticate
  users or lock the session.
- Interactive art and glyph canvases animate continuously; mind the cost when several are
  instantiated at once.

## Layout

| Family          | Design                                      | Folder                                                 | Widget ID                                          |
| --------------- | ------------------------------------------- | ------------------------------------------------------ | -------------------------------------------------- |
| Quick notes     | Notes a cassette                            | `quick-notes/cassette/`                                | `quick-notes-cassette`                             |
| Quick notes     | Notes b index                               | `quick-notes/index/`                                   | `quick-notes-index`                                |
| Quick notes     | Notes c console                             | `quick-notes/console/`                                 | `quick-notes-console`                              |
| Quick notes     | Notes d ash                                 | `quick-notes/ash/`                                     | `quick-notes-ash`                                  |
| Quick notes     | Notes preview                               | `quick-notes/preview/`                                 | `quick-notes-preview`                              |
| Quick notes     | Notes refined                               | `quick-notes/refined/`                                 | `quick-notes-refined`                              |
| Player          | Player directions / Ledger                  | `player/ledger/`                                       | `player-ledger`                                    |
| Player          | Player directions / Matrix                  | `player/matrix/`                                       | `player-matrix`                                    |
| Player          | Player directions / Rail                    | `player/rail/`                                         | `player-rail`                                      |
| Player          | Player directions / Sleeve                  | `player/sleeve/`                                       | `player-sleeve`                                    |
| Player          | Player directions / Title                   | `player/title/`                                        | `player-title`                                     |
| Glyphs          | Branch grammar                              | `glyphs/branch-grammar/`                               | `glyphs-branch-grammar`                            |
| Glyphs          | Formation field                             | `glyphs/formation-field/`                              | `lockscreen-reactive-lockscreen-studies-fo-efe52f` |
| Glyphs          | Glyph Bay typing                            | `glyphs/glyph-bay-typing/`                             | `glyphs-glyph-bay-typing`                          |
| Glyphs          | Oblique ligatures                           | `glyphs/oblique-ligatures/`                            | `glyphs-oblique-ligatures`                         |
| Glyphs          | Punch record                                | `glyphs/punch-record/`                                 | `lockscreen-mechanical-lockscreen-studies-e940db`  |
| Glyphs          | Radical exchange                            | `glyphs/radical-exchange/`                             | `glyphs-radical-exchange`                          |
| Glyphs          | Recursive relays                            | `glyphs/recursive-relays/`                             | `glyphs-recursive-relays`                          |
| Glyphs          | Shifted script                              | `glyphs/shifted-script/`                               | `glyphs-shifted-script`                            |
| Glyphs          | Shutter bank                                | `glyphs/shutter-bank/`                                 | `lockscreen-reactive-lockscreen-studies-sh-6c6cb4` |
| Glyphs          | Stencil assembly                            | `glyphs/stencil-assembly/`                             | `lockscreen-reactive-lockscreen-studies-st-69ba9c` |
| Glyphs          | Typesetter                                  | `glyphs/typesetter/`                                   | `lockscreen-reactive-lockscreen-studies-ty-e2b460` |
| Interactive art | Fish in space                               | `interactive-art/fish-in-space/`                       | `interactive-art-fish-in-space`                    |
| Interactive art | Gravity sandbox                             | `interactive-art/gravity-sandbox/`                     | `interactive-art-gravity-sandbox`                  |
| Interactive art | Magnetic powder                             | `interactive-art/magnetic-powder/`                     | `interactive-art-magnetic-powder`                  |
| Interactive art | Orbital playground                          | `interactive-art/orbital-playground/`                  | `interactive-art-orbital-playground`               |
| Interactive art | Resonance sculpture                         | `interactive-art/resonance-sculpture/`                 | `interactive-art-resonance-sculpture`              |
| Interactive art | Signal hunting                              | `interactive-art/signal-hunting/`                      | `interactive-art-signal-hunting`                   |
| Interactive art | Specimen chamber                            | `interactive-art/specimen-chamber/`                    | `interactive-art-specimen-chamber`                 |
| Lockscreens     | Afk layouts / Relay index / Relay tiles     | `lockscreens/afk-layouts/relay-index/relay-tiles/`     | `lockscreen-afk-layout-previews-relay-inde-bee7ea` |
| Lockscreens     | Afk layouts / Type folio / Relay tiles      | `lockscreens/afk-layouts/type-folio/relay-tiles/`      | `lockscreen-afk-layout-previews-type-folio-44fc03` |
| Lockscreens     | Editorial / Assembly mark / Compound glyph  | `lockscreens/editorial/assembly-mark/compound-glyph/`  | `lockscreen-editorial-studies-assembly-mar-4068d0` |
| Lockscreens     | Editorial / Foundry poster / Compound glyph | `lockscreens/editorial/foundry-poster/compound-glyph/` | `lockscreen-editorial-studies-foundry-post-598bff` |
| Lockscreens     | Editorial / Reverse print / Compound glyph  | `lockscreens/editorial/reverse-print/compound-glyph/`  | `lockscreen-editorial-studies-reverse-prin-7a2bf3` |
| Lockscreens     | Phase lock                                  | `lockscreens/phase-lock/formation/`                    | `tsugumori`                                        |
| Lockscreens     | Print / Index spine / Compound glyph        | `lockscreens/print/index-spine/compound-glyph/`        | `lockscreen-print-iterations-index-spine-c-26d6e1` |
| Lockscreens     | Print / Open masthead / Compound glyph      | `lockscreens/print/open-masthead/compound-glyph/`      | `lockscreen-print-iterations-open-masthead-08f5cf` |
| Lockscreens     | Reactive / Relay tiles                      | `lockscreens/reactive/relay-tiles/`                    | `lockscreen-reactive-lockscreen-studies-re-a37a9d` |

## Updating

Regenerate from a newer upstream revision and replace this tree:

```sh
git clone https://github.com/Aleph1-9012/Chaldea && cd Chaldea
make content                                            # packager -> build/content
cd frontend && bun run export <widget-id> <output-dir>  # one widget at a time
```

Copy each export into the folder from the table above, keeping upstream file names, then check the
tree with `bash scripts/dev/check-qml-syntax.sh .` from the repository root.

## Gates

`scripts/dev/check-qml-syntax.sh` parses every `.qml` file here. Two gates skip the vendored widget
folders by prefix: qmllint (`check-qml-lint.sh`) and the Markdown language gate
(`check-markdown-language.sh`) - upstream files stay unchanged, and the tree's inherent qmllint
findings (5 `property-override`, 4 `incompatible-type` at the revision above) must not fold into the
baseline that tracks this config's own QML. treefmt (`just fmt`) also leaves the widget folders
alone (see `treefmt.toml`), so the exports stay byte-identical; only this README is formatted with
the rest of the repository.
