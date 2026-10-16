# pleamar shell — frozen interfaces (PH1-T1)

Status: frozen 2026-10-16 by PH1-T1. Every PH2 scene, library and helper is written against this
document. If something here is wrong, it is fixed here first and the change is announced; nothing in
`shells/**` or `scripts/helpers/**` is allowed to define an interface this document does not.

Sources this document is derived from, read once and not to be edited by scene authors:

- `files/quickshell` (read-only legacy reference) — `Theme/manifest.json` + `Theme/*.jsonc` +
  `Theme/.theme.json`, `Settings/Theme.qml`, `Docs/ThemeHierarchical.json`,
  `Components/WidgetCapsule.qml`, `Components/CenteredCapsuleRow.qml`,
  `Components/CapsuleButton.qml`, `Components/PillIndicator.qml`,
  `Components/AudioLevelCapsule.qml`, `Helpers/CapsuleMetrics.js`, `Helpers/WidgetBg.js`.
- `pleamar --grammar` and `pleamar --docs reference|guide|recipes|logic` (version 0.4.11, language
  0.4). The compiler is the only authority on syntax; this document freezes the *interfaces*, not
  the language.
- `/etc/nixos/.agent/plans/2026-10-16-pleamar-superplan.xml` — `<design-decisions>` D1–D8 and the
  module spec.

Verification rule for everything here: `pleamar --check <scene>` after every edit. A library file
cannot be checked alone (the compiler says `this is a library: it is not opened`); libraries are
checked through a small consumer scene. Keep consumers in `/tmp`, never in the repo.

## 1. Files, deployment and import conventions

### 1.1 Repo layout

```
files/pleamar/
  lib/palette.plm            tokens: colours, sizes, type, timers, springs   (this PH1)
  lib/capsule.plm            the widget background component                 (this PH1)
  lib/menu.plm               menu rows, frozen in §5, not written yet        (next lib task)
  lib/icons.plm              icon helpers, frozen in §5.3, not written yet   (next lib task)
  shells/<scene>/<scene>.plm the scene; directory name == scene name == IPC name
  shells/<scene>/<scene>.luau its logic, optional, next to the scene
  shells/<scene>/pages/*.plm parts of the scene (`include`, they do not import)
  docs/INTERFACES.md         this file
  README.md, AGENTS.md       project rules
```

Naming rule from `AGENTS.md`, unchanged: one directory per scene, and the directory name, the
`scene` name and the IPC name are the same string. No aliases. `notifications` is one scene,
`panels` is one scene (drawers are parts and names inside it, §2), `toast` is one scene — do not add
`panels-volume` or similar side scenes.

### 1.2 Deployment (owned by the module task, not by scenes)

The repo is linked read-only into `~/.config/pleamar`: `lib/` to `~/.config/pleamar/lib/`,
`shells/*` to `~/.config/pleamar/shells/*`. Runtime files are never written into that tree:

| what                                                                       | path                                                                                    | who writes                                   |
| -------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- | -------------------------------------------- |
| per-scene settings                                                         | `~/.local/share/pleamar/<scene>/settings.json` (or `<feature>.json` in the same folder) | the scene's own logic, through `files.write` |
| wallpaper theme                                                            | `~/.config/pleamar/theme.plm`                                                           | PH1-T2's theme script                        |
| cache / signal files                                                       | `~/.cache/pleamar/<name>`                                                               | the scene that owns the signal               |
| durable scene state                                                        | `~/.local/state/pleamar/<scene>/`                                                       | the scene's logic                            |
| pleamar's own per-scene folder (`files.read`/`files.write`/`files.folder`) | `~/.local/share/pleamar/<scene>/` (XDG_DATA_HOME)                                       | the logic                                    |

Two facts of the language shape all of this: a scene can only touch files in its own folder
(`no paths, no ..`), and the folder is `$XDG_DATA_HOME/pleamar/<scene>/`. So every settings file is
a bare name such as `settings.json`, `media.json`, `weather.json`.

Cross-scene signals are files, not imports: scenes never import each other and never read each
other's folders. The signal names reserved for PH2 (owner in brackets):

- `~/.cache/pleamar/dismiss-overlay` — overlay dismissal request [overlay, PH2-D]
- `~/.cache/pleamar/notif-close-all` — close every toast [notifications, PH2-C]
- `~/.cache/pleamar/screenshot-event.json` — screenshot toast payload [toast, PH2-D]
- `~/.cache/pleamar/wallpaper-path` — current wallpaper, for the theme script [PH1-T2]
- `~/.local/state/pleamar/bar/startup` — login gate state [bar, PH2-A]

The legacy `~/.cache/quickshell/*` and `~/.local/state/quickshell/*` paths stay where they are until
the cutover commit (the integration task owns that list); new scenes must not add new files there.

### 1.3 Imports

A scene at `shells/<scene>/<scene>.plm` imports the libraries with a path relative to itself:

```plm
import "../../lib/palette.plm"
import "../../lib/capsule.plm"
```

- Palette first, then capsule. `lib/capsule.plm` imports `lib/palette.plm` itself, so the defaults
  resolve even in a scene that forgets the first line, but scenes still import both explicitly: a
  scene reads every name it uses from somewhere in its own file.
- Library files import their siblings by bare name (`import "palette.plm"`).
- Parts (`shells/<scene>/pages/<part>.plm`, pulled in with `include`) **do not import**. The scene
  imports the libraries; a part uses the names the scene imported. A part has no name of its own and
  is not checked alone.
- No scene imports another scene and no library under `lib/` is scene-specific.
- Components from an imported library are called by their own name (`Capsule(...)`). Add a surname
  (`import "../../lib/menu.plm" as menu`, then `menu.Action(...)`) only when two imported libraries
  have a component with the same name. A library may have only one name per scene — importing it
  twice, once with a surname and once without, is an error.

### 1.4 theme.plm (wallpaper palette, PH1-T2)

`~/.config/pleamar/theme.plm` is generated by PH1-T2 and imported by scenes that want the wallpaper
palette:

```plm
import "../../lib/palette.plm"
import "../../theme.plm"          // after palette
```

Frozen rule: **theme.plm must not declare a name that `palette.plm` declares.** The compiler only
warns about a re-declared `let` — “this one changes what `x` means in everything after it, and in a
scene copied per monitor each copy may take one or the other” — and that warning is a real hazard
for every `screens: each` scene (the copies are made while imports are being read). theme.plm
therefore declares names under its own `skin.` prefix (`skin.accent`, `skin.surface`, `skin.ink`,
`skin.ink.dim`, …), and a scene that opts into the wallpaper look uses `skin.*` names explicitly.

For a palette that changes while the scene runs (wallpaper switch without a reload), use the
language's own runtime route instead: three facts (for example `pal.red`, `pal.green`, `pal.blue`)
set by the logic, and `let live = rgb(pal.red, pal.green, pal.blue)` in the scene. `rgb()` takes
three 0–1 numbers and is the only colour that can come from facts.

## 2. Scene catalog and IPC names

The seven scene processes of the port, with their names fixed here. The IPC name is the scene name:
`pleamar --say <name> …` (unit `pleamar-<name>.service`). One scene per process, one or more
surfaces inside it (D1/D2), never a popup for a drawer.

| scene           | file                                     | surface                                                                                                                                                        | purpose                                                                                                                              | owner  |
| --------------- | ---------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ | ------ |
| `bar`           | `shells/bar/bar.plm`                     | one per monitor (`screens: each`), anchor from settings (`bottom` on trantor), `size: full, bar.height * scale + shadow room`, `reserve: <height> while shown` | the strip and its widgets: clock, workspaces, volume, network, battery, media, weather, keyboard, tray, system monitor, startup gate | PH2-A  |
| `panels`        | `shells/panels/panels.plm`               | one per monitor (`screens: each`), anchor `top`, `level: overlay`, `reserve: 0`, open while a drawer is open                                                   | every drawer hanging from the bar: music, weather, network, calendar, mixer, tray menus, system monitor, settings                    | PH2-B  |
| `notifications` | `shells/notifications/notifications.plm` | one per monitor for the centre, plus the toast placement it owns                                                                                               | notification centre, persistent history, DND, actions, images; it is the `org.freedesktop.Notifications` server while it runs (D6)   | PH2-C  |
| `toast`         | `shells/toast/toast.plm`                 | one per monitor, `level: overlay`, `agent: hidden` on decorative parts                                                                                         | transient stacked toasts (max 2), screenshot toast with OCR actions                                                                  | PH2-D  |
| `overlay`       | `shells/overlay/overlay.plm`             | one per monitor, full size, `level: overlay`                                                                                                                   | full-screen dismissal catcher (`dismiss-overlay`), clear-all (`notif-close-all`), idle-inhibitor equivalent                          | PH2-D  |
| `lock`          | `shells/lock/lock.plm`                   | `kind: lock` (ext-session-lock), one copy per monitor                                                                                                          | the session lock screen; owns the login phase later (PH3-L)                                                                          | PH3-L  |
| `launcher`      | `shells/launcher/launcher.plm`           | one per monitor, `level: overlay`                                                                                                                              | application launcher and search                                                                                                      | PH3-O  |
| `theme`         | `shells/theme/theme.plm`                 | small helper surface, optional                                                                                                                                 | wallpaper → `theme.plm` bridge and live accent facts                                                                                 | PH1-T2 |

### 2.1 Facts a scene exposes for IPC and for the other scenes

Only these names are interface; everything else in a scene is private and may change without notice.
Read them with `pleamar --say <scene> "get <fact>"` and set them with
`pleamar --say <scene> "fact <name> <value>"`.

| scene           | fact / text | type                                                                                                                                           | default | meaning                                                                                      |
| --------------- | ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | ------- | -------------------------------------------------------------------------------------------- |
| `bar`           | `shown`     | bool                                                                                                                                           | `true`  | the strip is there; `reserve` counts only while true                                         |
| `bar`           | `startup`   | bool                                                                                                                                           | `false` | login gate is up (clean bar) — written by its logic, read by tests                           |
| `panels`        | `drawer`    | enum `none \| volume \| microphone \| network \| bluetooth \| media \| calendar \| weather \| keyboard \| tray \| system \| power \| settings` | `none`  | which drawer is open (one at a time, D1)                                                     |
| `notifications` | `dnd`       | bool                                                                                                                                           | `false` | do not disturb                                                                               |
| `notifications` | `centre`    | bool                                                                                                                                           | `false` | the notification centre is open                                                              |
| `notifications` | `count`     | number                                                                                                                                         | `0`     | notifications currently shown or kept (read-only for other scenes)                           |
| `toast`         | `visible`   | number                                                                                                                                         | `0`     | how many toasts are on screen                                                                |
| `overlay`       | `active`    | bool                                                                                                                                           | `false` | the dismissal catcher is up                                                                  |
| `lock`          | `locked`    | bool                                                                                                                                           | `false` | the lock surface wants the session (the compositor's own `lock.held` says whether it has it) |
| `launcher`      | `open`      | bool                                                                                                                                           | `false` | the launcher is up                                                                           |
| `launcher`      | `query`     | text                                                                                                                                           | `""`    | what has been typed                                                                          |

IPC examples that other tools (Hyprland binds, health probe, scripts) may rely on:

```sh
pleamar --say bar "get shown"
pleamar --say panels "fact drawer volume"
pleamar --say panels "fact drawer none"
pleamar --say notifications "fact dnd true"
pleamar --say notifications "emit dismiss_all"     # if the scene declares it
pleamar --say overlay "fact active true"
pleamar --say launcher "fact open true"
pleamar --say launcher "text query kitty"
```

Enum facts accept their value names over IPC (the compiler checks them): `fact drawer volume`, not
`2`. Booleans accept `true` / `false`. One command per argument; `--say` takes several commands in
order.

### 2.2 The drawer names (the `panels/*` family)

`panels/*` is the shell's name for the drawer family; each entry is a *drawer name*, not a scene,
and all of them live in the one `panels` process:

`volume`, `microphone`, `network`, `bluetooth`, `media`, `calendar`, `weather`, `keyboard`, `tray`,
`system`, `power`, `settings`.

Each drawer is a part under `shells/panels/pages/<name>.plm` (owned by PH2-B), included by
`panels.plm`; a drawer that is too big for a part may be split into more parts, but the drawer name
is fixed. Opening/closing is the `drawer` fact alone; the bar's widgets never reach into `panels` —
the bar's button sets the fact by IPC (or calls `pleamar --say panels …` through its rules? pleamar
rules cannot run programs; the bar's *logic* does it with `run`/`spawn`, permission
`run: "pleamar"`), and `panels` closes on Escape, on outside press and when `drawer` is set to
`none`.

The names `none`, `volume`, …, `settings` are also the placeholders for the drawer titles: use the
label texts in §8 (`Volume`, `Microphone`, `Network`, `Bluetooth`, `Media`, `Calendar`, `Weather`,
`Keyboard`, `Tray`, `System monitor`, `Power`, `Settings`).

### 2.3 Surfaces, screens and reserve

- Bar and panels are separate processes on purpose (crash isolation, disjoint writers). The bar
  keeps the reserve; `panels` is `level: overlay` and reserves nothing, so a full-screen window
  still reaches under it (D2).
- Every per-monitor scene declares `screens: each`. Inside the copies, `$screen`, `screen.index`,
  `screen.name`, `screen.width`, `screen.height` are the copy's own, and every geometry expression
  that must differ per monitor is written *inside* the repeated drawing (see §3.2 — loose `let`s,
  `prop`s and `fact`s are shared by all copies).
- The bar's surface carries the shadow room the QS theme expected: a body shadow of `0, 2, 6` needs
  4 px below the strip, so `size: full, bar.height * scale + 4 * scale` with the strip drawn in the
  top `bar.height * scale`, or anchor the surface where the shadow cannot be cut (§5.3 of the
  reference: a cut shadow is a renderer message, not an error, but it is a visible defect).

## 3. Palette (`lib/palette.plm`)

`lib/palette.plm` is a strict library of `let` names and `spring`s. It declares nothing else (no
facts, no events, no drawing) so importing it can never change a scene's behaviour. A scene imports
it once and may re-declare any name to tune it; the shell look comes from not doing so.

The palette is the Quickshell theme translated name for name — the full table is in §3.3. Where QS
had a colour with alpha, the palette splits it into a tone (`coal`, `ink`, `warn`, …) and an alpha
number (`veil`, `ink.hover`, `shadow`, …): **a pleamar colour literal is `#rgb` or `#rrggbb`, it
cannot carry alpha**. Apply the alpha at the drawing site (`opacity: veil`, `fill: ink ink.hover`)
or let the capsule do it (§4).

### 3.1 Design pixels and the base scale

Every length in the palette is a **design pixel** — the number the QS theme uses (`panel.height` 22,
`cornerRadius` 6, `type.small` 14, …). Sizes in scenes are written as `<design length> * <scale>`;
the scale is `ui` (1.15, the QS `panel.scale`) in a single-surface scene, and a per-monitor value in
a `screens: each` scene (§3.2). Type sizes additionally carry the user's `type.scale` / settings
`fontScale`.

`lib/capsule.plm` multiplies its own lengths by the `scale` parameter (default `ui`), so a capsule
call passes design sizes:

```plm
Capsule(140, 34, shadow: 25%) {               // 140 × 34 design px
    text "wifi" { size: 12 * ui; color: ink } // content: the caller scales
}
```

Qt font sizes were integers in QS; `12 * ui` = 13.8 is fine — pleamar takes fractional sizes, and
rounding them is a defect (it makes 1.15 and 2.0 monitors disagree).

### 3.2 The per-monitor scale model

There is no per-monitor settings channel in pleamar and **no per-copy `let`**: a loose `let`, `prop`
or `fact` is one for all the copies of a `screens: each` scene (the reference says so explicitly and
warns about `follow a = screen.index`). The only per-copy channels are the drawing expressions
themselves, where `screen.*` belongs to the copy, and component parameters (a copy of a component in
the repeated drawing gets its own parameters).

Frozen expression — call it `scaleNow` in scene comments, write it out where it is used:

```
ui * clamp(min(screen.width / design.width, screen.height / design.height), fit.min, fit.max)
```

- `ui` = 1.15, `design.width` = 1920, `design.height` = 1080, `fit.min` = 0.8, `fit.max` = 1.5 (the
  logical reference is this machine's DP-2, `nx2160@240` at Hyprland scale 2).
- On the reference monitor it is exactly 1.15 — the QS look; elsewhere it fits the UI to the monitor
  instead of the QS `monitorScaleOverrides` map, which pleamar has no channel for.
- Use it **inside the repeated drawing**: as the `scale:` argument of `Capsule` and every lib
  component, and as the multiplier of every other design length and text size in the copy. In a
  single-surface scene use `ui` alone, because there `screen.width` and `screen.height` measure the
  *surface*, not the monitor.
- Scenes that want a user knob on top read `settings.json` in their logic and expose the result
  through a model filled per monitor index (one record per `screen.index`); the drawing then
  multiplies by `monitors.$screen.scale` as well. This is optional — the expression above is the
  default and needs no logic.
- Do not put the expression in a loose `let`, `prop` or `fact`: the copies would race for it (see
  the compiler's own warning).

Because the expression is long, define the convention at the top of each per-monitor scene as a
comment, and keep the multiplications uniform: every length multiplied by `scaleNow *` exactly once,
no unscaled literals left (a 13 px text on a 2.0-scaled monitor is a bug the screenshot review will
catch).

### 3.3 The QS → palette mapping

The table is the whole palette: every `let` in `lib/palette.plm` is here, with the Quickshell token
it replaces and the value it holds. A blank note means the value is the QS token's value unchanged.
`value` is the palette's declaration; derived colours (`accent.hover`, …) are the `mix()`
expression, evaluated when the scene loads.

#### Colours — base and text

| QS token                | palette name | value     | note                                      |
| ----------------------- | ------------ | --------- | ----------------------------------------- |
| `colors.background`     | `coal`       | `#000000` | #ff000000, opaque part                    |
| `colors.surface`        | `veil`       | `53%`     | #88000000 → alpha 136/255 ≈ 53% over coal |
| `colors.surfaceVariant` | `slate`      | `#242A35` |                                           |
| `colors.outline`        | `outline`    | `#3B4C5C` |                                           |
| `colors.text.primary`   | `ink`        | `#CBD6E5` |                                           |
| `colors.text.secondary` | `ink.dim`    | `#AEB9C8` |                                           |
| `colors.text.disabled`  | `ink.off`    | `#6B718A` |                                           |

#### Colours — veils and shadow

| QS token              | palette name    | value | note                                                                |
| --------------------- | --------------- | ----- | ------------------------------------------------------------------- |
| `Theme.surfaceHover`  | `ink.hover`     | `6%`  | ink at 6% (QS Color.withAlpha(textPrimary, 0.06))                   |
| `Theme.surfaceActive` | `ink.active`    | `10%` | ink at 10%                                                          |
| `Theme.borderSubtle`  | `ink.subtle`    | `15%` | ink at 15%                                                          |
| `colors.shadow`       | `shadow`        | `70%` | #B3000000 after Theme.applyOpacity(..., "B3") → alpha 179/255 ≈ 70% |
| `Theme.overlayWeak`   | `shadow.weak`   | `8%`  | shadow at 8%                                                        |
| `Theme.overlayStrong` | `shadow.strong` | `18%` | shadow at 18%                                                       |
| `(new)`               | `shadow.dx`     | `0`   | the usual QS shadow offset 0, 2, 6                                  |
| `(new)`               | `shadow.dy`     | `2`   | the usual QS shadow offset 0, 2, 6                                  |
| `(new)`               | `shadow.blur`   | `6`   | the usual QS shadow offset 0, 2, 6                                  |

#### Colours — accent and status

| QS token                 | palette name   | value                       | note                                                                         |
| ------------------------ | -------------- | --------------------------- | ---------------------------------------------------------------------------- |
| `colors.accent.primary`  | `accent`       | `#006FCC`                   | wallpaper hue-matched at runtime (Theme.accentPrimary); this is the fallback |
| `Theme.accentHover`      | `accent.hover` | `mix(accent, #ffffff, 20%)` | towards white 20%                                                            |
| `Theme.accentDarkStrong` | `accent.deep`  | `mix(accent, coal, 80%)`    | towards black 80%                                                            |
| `colors.onAccent`        | `on.accent`    | `#FFFFFF`                   |                                                                              |
| `colors.highlight`       | `highlight`    | `#94E1F9`                   |                                                                              |
| `colors.status.error`    | `warn`         | `#FF6B81`                   | the house word for the error role; QS hue kept                               |
| `colors.status.warning`  | `amber`        | `#FFB347`                   |                                                                              |
| `panel.pill.color`       | `pill`         | `#000000`                   |                                                                              |

#### Colours — volume and notifications

| QS token                    | palette name    | value     | note |
| --------------------------- | --------------- | --------- | ---- |
| `panel.volume.lowColor`     | `volume.low`    | `#D62E6E` |      |
| `panel.volume.highColor`    | `volume.high`   | `#0E6B4D` |      |
| `notifications.background`  | `notify.tone`   | `#000000` |      |
| `notifications.foreground`  | `notify.ink`    | `#E0E6EF` |      |
| `notifications.frameColor`  | `notify.frame`  | `#000000` |      |
| `notifications.accentColor` | `notify.accent` | `#004E8F` |      |

#### Colours — lock (greeter)

| QS token                        | palette name        | value     | note                                             |
| ------------------------------- | ------------------- | --------- | ------------------------------------------------ |
| `greeter.accentColor`           | `lock.accent`       | `#7FD6FF` |                                                  |
| `greeter.dangerColor`           | `lock.danger`       | `#FF9B9B` |                                                  |
| `greeter.textColor`             | `lock.ink`          | `#F2F6FA` |                                                  |
| `greeter.textMutedColor`        | `lock.ink.dim`      | `#C3D2E0` |                                                  |
| `greeter.cardColor`             | `lock.card`         | `#0F141C` | #a60f141c → color part; alpha in lock.card.alpha |
| `greeter.cardColor`             | `lock.card.alpha`   | `65%`     | 0xa6 ≈ 65%                                       |
| `greeter.widgetColor`           | `lock.widget`       | `#CEFFFF` | #25ceffff → color part                           |
| `greeter.widgetColor`           | `lock.widget.alpha` | `15%`     | 0x25 ≈ 15%                                       |
| `greeter.widgetActiveColor`     | `lock.widget.on`    | `50%`     | #80ceffff → 0x80 ≈ 50%                           |
| `greeter.widgetOutline`         | `lock.edge`         | `#FFFFFF` | #40ffffff → color part                           |
| `greeter.widgetOutline`         | `lock.edge.alpha`   | `25%`     | #40 ≈ 25%                                        |
| `greeter.widgetOutlineSeparate` | `lock.edge.soft`    | `13%`     | #20 ≈ 13%                                        |
| `greeter.separatorColor`        | `lock.seam`         | `#FFFFFF` | #60ffffff → color part                           |
| `greeter.separatorColor`        | `lock.seam.alpha`   | `38%`     | #60 ≈ 38%                                        |

#### Shape and spacing

| QS token                   | palette name      | value  | note                    |
| -------------------------- | ----------------- | ------ | ----------------------- |
| `shape.cornerRadius`       | `corner`          | `6`    |                         |
| `shape.cornerRadiusSmall`  | `corner.small`    | `6`    | capsule default         |
| `shape.cornerRadiusLarge`  | `corner.large`    | `0`    |                         |
| `panel.overlayRadius`      | `overlay.corner`  | `5`    |                         |
| `panel.height`             | `bar.height`      | `22`   |                         |
| `panel.moduleHeight`       | `bar.module`      | `22`   |                         |
| `panel.sideMargin`         | `bar.side`        | `4`    |                         |
| `panel.widgetSpacing`      | `bar.gap`         | `4`    |                         |
| `panel.rowSpacing`         | `bar.row`         | `4`    |                         |
| `panel.rowSpacingSmall`    | `bar.row.small`   | `2`    |                         |
| `panel.hotzone.width`      | `bar.hot`         | `16`   |                         |
| `panel.hotzone.height`     | `bar.hot.height`  | `9`    |                         |
| `panel.hotzone.rightShift` | `bar.hot.shift`   | `1.15` |                         |
| `panel.menuYOffset`        | `bar.menu.offset` | `20`   |                         |
| `panel.seamWidthRatio`     | `bar.seam`        | `0.85` |                         |
| `panel.seamMinPx`          | `bar.seam.min`    | `8`    |                         |
| `panel.separatorOpacity`   | `bar.seam.alpha`  | `88%`  | also panel.seam.opacity |
| `panel.interWidgetRatio`   | `bar.inter`       | `1.35` |                         |

#### Icons, pills, capsule

| QS token                         | palette name        | value  | note                                                                          |
| -------------------------------- | ------------------- | ------ | ----------------------------------------------------------------------------- |
| `panel.icons.iconSize`           | `icon.size`         | `24`   |                                                                               |
| `panel.icons.iconSizeSmall`      | `icon.small`        | `16`   |                                                                               |
| `ui.iconSizeLarge`               | `icon.large`        | `28`   |                                                                               |
| `ui.control.height`              | `control.height`    | `48`   |                                                                               |
| `ui.visibilityEpsilon`           | `vis.epsilon`       | `0.01` |                                                                               |
| `panel.pill.height`              | `pill.height`       | `28`   |                                                                               |
| `panel.pill.iconSize`            | `pill.icon`         | `22`   |                                                                               |
| `panel.pill.paddingH`            | `pill.pad`          | `8`    |                                                                               |
| `ui.spacing.xsmall`              | `capsule.pad`       | `4`    | CapsuleMetrics.padding: max(2, round(4 * scale))                              |
| `CapsuleMetrics verticalPadding` | `capsule.pad.y`     | `2`    | max(2, round(padding * 0.6)) → 2                                              |
| `CapsuleMetrics height`          | `capsule.height`    | `18`   | inner (round(fontSizeSmall * time.font.scale) = 10) + 2 * pad → 18            |
| `CapsuleButton.iconSpacing`      | `capsule.gap`       | `2`    | panel.rowSpacingSmall                                                         |
| `panel.capsule.borderWidth`      | `capsule.edge`      | `0`    | 0 in the shipped theme                                                        |
| `panel.capsule.borderColor`      | `capsule.edge.tone` | `coal` | the shipped override is #000000                                               |
| `panel.capsule.borderOpacity`    | `capsule.edge.soft` | `8%`   | the hairline alpha; invisible in the shipped theme because `borderWidth` is 0 |

#### Tooltip, menu, side panel

| QS token                             | palette name        | value  | note |
| ------------------------------------ | ------------------- | ------ | ---- |
| `tooltip.delayMs`                    | `tooltip.delay`     | `150`  |      |
| `tooltip.minSize`                    | `tooltip.min`       | `20`   |      |
| `tooltip.margin`                     | `tooltip.margin`    | `12`   |      |
| `tooltip.padding`                    | `tooltip.pad`       | `8`    |      |
| `tooltip.borderWidth`                | `tooltip.edge`      | `1`    |      |
| `tooltip.radius`                     | `tooltip.corner`    | `2`    |      |
| `tooltip.fontPx`                     | `tooltip.type`      | `12`   |      |
| `tooltip.smallScaleRatio`            | `tooltip.scale`     | `0.71` |      |
| `panel.menu.width`                   | `menu.width`        | `180`  |      |
| `panel.menu.submenuWidth`            | `menu.width.sub`    | `180`  |      |
| `panel.menu.padding`                 | `menu.pad`          | `4`    |      |
| `panel.menu.itemSpacing`             | `menu.item.gap`     | `2`    |      |
| `panel.menu.itemHeight`              | `menu.item.height`  | `26`   |      |
| `panel.menu.itemRadius`              | `menu.item.corner`  | `0`    |      |
| `panel.menu.radius`                  | `menu.corner`       | `0`    |      |
| `panel.menu.heightExtra`             | `menu.extra`        | `12`   |      |
| `panel.menu.anchorYOffset`           | `menu.offset`       | `4`    |      |
| `panel.menu.submenuGap`              | `menu.sub.gap`      | `12`   |      |
| `panel.menu.chevronSize`             | `menu.chevron`      | `15`   |      |
| `panel.menu.iconSize`                | `menu.icon`         | `16`   |      |
| `panel.menu.itemFontScale`           | `menu.type`         | `0.9`  |      |
| `sidePanel.spacing`                  | `side.pad`          | `6`    |      |
| `sidePanel.spacingTight`             | `side.pad.tight`    | `3`    |      |
| `sidePanel.spacingSmall`             | `side.pad.small`    | `2`    |      |
| `sidePanel.spacingMedium`            | `side.pad.medium`   | `4`    |      |
| `sidePanel.cornerRadius`             | `side.corner`       | `0`    |      |
| `sidePanel.innerRadius`              | `side.corner.inner` | `0`    |      |
| `sidePanel.buttonHoverRadiusFactor`  | `side.corner.hover` | `0.5`  |      |
| `sidePanel.selector.minWidth`        | `side.selector`     | `120`  |      |
| `sidePanel.albumArtSize`             | `side.art`          | `200`  |      |
| `sidePanel.popup.glassOpacity`       | `side.glass`        | `75%`  |      |
| `sidePanel.popup.glassBorderOpacity` | `side.edge`         | `10%`  |      |
| `sidePanel.popup.outerMargin`        | `side.margin`       | `4`    |      |

#### Workspaces, keyboard, calendar, network

| QS token                       | palette name        | value  | note |
| ------------------------------ | ------------------- | ------ | ---- |
| `ws.icon.scale`                | `ws.scale`          | `1.4`  |      |
| `ws.icon.detachedScale`        | `ws.scale.detached` | `1.15` |      |
| `ws.icon.spacing`              | `ws.gap`            | `1`    |      |
| `ws.icon.svgScale`             | `ws.svg`            | `0.52` |      |
| `ws.icon.innerPadding`         | `ws.pad`            | `1`    |      |
| `ws.label.leftPadding.normal`  | `ws.label`          | `6`    |      |
| `keyboard.capsule.minLabelGap` | `keyboard.min`      | `3`    |      |
| `panel.netCluster.spacing`     | `network.cluster`   | `2`    |      |
| `calendar.rowSpacing`          | `calendar.row`      | `2`    |      |
| `calendar.cellSpacing`         | `calendar.cell`     | `2`    |      |
| `calendar.sideMargin`          | `calendar.side`     | `2`    |      |
| `calendar.popupMargin`         | `calendar.popup`    | `2`    |      |

#### Media, spectrum, VPN, weather

| QS token                             | palette name           | value  | note |
| ------------------------------------ | ---------------------- | ------ | ---- |
| `media.hover.openDelayMs`            | `media.hover.delay`    | `320`  |      |
| `media.hover.stillThresholdMs`       | `media.hover.still`    | `180`  |      |
| `media.artDebounceMs`                | `media.art.debounce`   | `60`   |      |
| `media.accent.retryMs`               | `media.accent.retry`   | `120`  |      |
| `media.accent.retryMax`              | `media.accent.tries`   | `5`    |      |
| `media.icon.panel.overlayPaddingPx`  | `media.panel.pad`      | `12`   |      |
| `media.icon.panel.overlayBgOpacity`  | `media.panel.veil`     | `65%`  |      |
| `media.icon.panel.overlayWidthShare` | `media.panel.share`    | `0.45` |      |
| `media.albumArt.fallbackOpacity`     | `media.art.fade`       | `40%`  |      |
| `spectrum.peakDecayIntervalMs`       | `spectrum.decay`       | `50`   |      |
| `spectrum.barAnimMs`                 | `spectrum.anim`        | `100`  |      |
| `spectrum.barGap`                    | `spectrum.gap`         | `2`    |      |
| `spectrum.minBarWidth`               | `spectrum.bar.min`     | `2`    |      |
| `spectrum.peakOpacity`               | `spectrum.peak.alpha`  | `70%`  |      |
| `spectrum.fillOpacity`               | `spectrum.fill.alpha`  | `35%`  |      |
| `spectrum.peakThickness`             | `spectrum.peak.height` | `2`    |      |
| `vpn.accent.saturateBoost`           | `vpn.saturate`         | `0.12` |      |
| `vpn.desaturateAmount`               | `vpn.desaturate`       | `0.45` |      |
| `weather.headerScale`                | `weather.header`       | `0.75` |      |
| `weather.centerOffset`               | `weather.offset`       | `-2`   |      |
| `weather.httpTimeoutMs`              | `weather.timeout`      | `8000` |      |

#### Typography

| QS token                             | palette name     | value | note                                                         |
| ------------------------------------ | ---------------- | ----- | ------------------------------------------------------------ |
| `Theme.fontSizeHeader`               | `type.header`    | `32`  | 32 × fontSizeMultiplier                                      |
| `Theme.fontSizeBody`                 | `type.body`      | `16`  | 16 × fontSizeMultiplier                                      |
| `Theme.fontSizeSmall`                | `type.small`     | `14`  | 14 × fontSizeMultiplier                                      |
| `Theme.fontSizeCaption`              | `type.caption`   | `12`  | 12 × fontSizeMultiplier                                      |
| `Settings.json fontSizeMultiplier`   | `type.scale`     | `1.0` | runtime value; scene reads it and multiplies the sizes above |
| `panel.computedFontScale`            | `type.inline`    | `0.6` | 0.6, clamped 0.1–2.0                                         |
| `Font weight`                        | `weight.regular` | `400` |                                                              |
| `Font.Medium / Theme.timeFontWeight` | `weight.medium`  | `500` |                                                              |
| `Font.Bold`                          | `weight.bold`    | `600` |                                                              |
| `time.font.scale`                    | `time.scale`     | `0.7` |                                                              |
| `time.font.weight`                   | `time.weight`    | `500` |                                                              |
| `time.text.color`                    | `time.tone`      | `ink` |                                                              |

#### Timers

| QS token                             | palette name          | value      | note                    |
| ------------------------------------ | --------------------- | ---------- | ----------------------- |
| `timers.timeTickMs`                  | `time.tick`           | `1000`     |                         |
| `timers.wsRefreshDebounceMs`         | `ws.debounce`         | `120`      |                         |
| `timers.genericTickMs`               | `tick.generic`        | `2000`     |                         |
| `timers.musicPositionPollMs`         | `music.position`      | `1000`     |                         |
| `timers.musicPlayersPollMs`          | `music.players`       | `5000`     |                         |
| `timers.musicMetaRecalcDebounceMs`   | `music.meta`          | `80`       |                         |
| `media.mpd.flags.fallbackMs`         | `mpd.flags`           | `2500`     |                         |
| `network.vpnPollMs`                  | `vpn.poll`            | `2500`     |                         |
| `network.restartBackoffMs`           | `network.backoff`     | `1500`     |                         |
| `network.linkPollMs`                 | `network.link`        | `4000`     |                         |
| `ui.anim.quickMs`                    | `anim.quick`          | `120`      | also panel.hover.fadeMs |
| `ui.anim.rotateMs`                   | `anim.rotate`         | `160`      |                         |
| `ui.spinner.durationMs`              | `anim.spinner`        | `1000`     |                         |
| `panel.animations.fastMs`            | `anim.fast`           | `150`      |                         |
| `panel.animations.stdMs`             | `anim.std`            | `200`      |                         |
| `panel.animations.overlayMs`         | `anim.overlay`        | `180`      |                         |
| `panel.animations.slideMs`           | `anim.slide`          | `380`      |                         |
| `greeter.animFastMs`                 | `anim.greeter.fast`   | `150`      |                         |
| `greeter.animMediumMs`               | `anim.greeter`        | `250`      |                         |
| `greeter.animSlowMs`                 | `anim.greeter.slow`   | `500`      |                         |
| `greeter.lockAnimationMs`            | `anim.lock`           | `500`      |                         |
| `panel.pill.showDelayMs`             | `pill.show`           | `500`      |                         |
| `panel.pill.autoHidePauseMs`         | `pill.pause`          | `2500`     |                         |
| `panel.tray.longHoldMs`              | `tray.long`           | `2500`     |                         |
| `panel.tray.shortHoldMs`             | `tray.short`          | `1500`     |                         |
| `panel.tray.guardMs`                 | `tray.guard`          | `120`      |                         |
| `panel.tray.overlayDismissDelayMs`   | `tray.dismiss`        | `5000`     |                         |
| `panel.tray.inlinePadding`           | `tray.pad`            | `4`        |                         |
| `panel.volume.fullHideMs`            | `volume.hide`         | `800`      |                         |
| `panel.volume.mutedHideMs`           | `volume.hide.muted`   | `180000`   |                         |
| `panel.volume.offReminderCooldownMs` | `volume.off.cooldown` | `86400000` |                         |
| `volume.icon.offThreshold`           | `volume.icons.off`    | `0`        |                         |
| `volume.icon.downThreshold`          | `volume.icons.down`   | `30`       |                         |
| `volume.icon.upThreshold`            | `volume.icons.up`     | `50`       |                         |
| `panel.slideTimerTickMs`             | `tick.bar`            | `16`       |                         |

#### Scale model (new, not a QS token)

| QS token      | palette name    | value  | note                                                                                |
| ------------- | --------------- | ------ | ----------------------------------------------------------------------------------- |
| `panel.scale` | `ui`            | `1.15` | × Settings.json fontSizeMultiplier (default 1.0), clamped 0.25–2.5 in QS            |
| `(new)`       | `design.width`  | `1920` | logical width of the reference monitor (DP-2 nx2160@240 at scale 2 → 1920×1080)     |
| `(new)`       | `design.height` | `1080` | logical height of the reference monitor                                             |
| `(new)`       | `fit.min`       | `0.8`  | lower clamp for the per-monitor scale; replaces Settings.json monitorScaleOverrides |
| `(new)`       | `fit.max`       | `1.5`  | upper clamp for the per-monitor scale                                               |

#### Springs

| palette name | stiffness, damping | ≈ arrival |
| ------------ | ------------------ | --------- |

### 3.4 Colour use, in practice

- Text on a capsule: `ink`; secondary text `ink.dim`; disabled `ink.off`.
- A hover wash over a capsule: `fill: ink ink.hover` (a layout fill takes a colour and an opacity)
  or a box `color: ink; opacity: ink.hover * hit.hover`. QS used a colour with alpha; pleamar uses
  the same numbers with `opacity`.
- The bar and panels sit on `coal` with `veil` (53%) for translucent capsules; a drawer that must
  hide what is under it uses `alpha: 1`.
- `warn` = the QS error red, `amber` = warning yellow, `highlight` = the pale cyan highlight,
  `accent` = the blue fallback for the wallpaper-matched accent. When the theme pipeline provides
  the wallpaper accent, use `skin.accent` (and its `mix()`es in the scene) or the `rgb()` facts from
  §1.4.
- There is no `mint` in this palette. `mint` (#9ed6bd) appears in the pleamar documentation's own
  examples but is **not** a Quickshell theme token; keeping it would have moved the shell's accent
  from the blue `#006FCC` to a green the legacy shell never showed. A scene that wants the
  documentation look declares `let mint = #9ed6bd` in its own file — one line, no library change.

### 3.5 Springs

The six springs in the table above replace the QS animation timings; they are critically damped to
arrive in about the time the QS `duration`/`easing` pair took. Use them as `~ui.std`, `~ui.slide`, …
A one-off duration can still be written inline (`~620ms`), and the house springs (`~quick`, `~calm`,
…) stay available for things that are not theme timings. With `--reduced-motion` and a user's
`reducedMotion` setting, springs settle at once; scenes do not need to branch for that (the renderer
does it), but `spin`, `wave` and `blink` go quiet on their own.

## 4. Capsule API (`lib/capsule.plm`)

The capsule is the one background every widget uses; it is the pleamar form of
`Components/WidgetCapsule.qml` — box, corner, rim, optional edge and shadow, a content slot. It
draws no zone and emits no event: the widget that uses it owns the interactive zone (and its
`label:`/`role:`/`agent:` policy, §8). The contract in QS terms:

| QS (`WidgetCapsule.qml`)               | pleamar                                                                                                   |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `color` (`WidgetBg`/`Theme.surface`)   | `fill` + `alpha` (defaults `slate` / `veil`)                                                              |
| corner radii, per-corner               | `radius` (one corner; a triangle overlay is not ported)                                                   |
| `horizontalPadding`, `verticalPadding` | `pad`, `pad_y`                                                                                            |
| content area, vertically centred       | the `content` row slot: `at: pad * scale, pad_y * scale`, `size: width - 2 * pad`, `align: center`, `gap` |
| `OverlayFrame` border                  | `edge` + `edge_tone` + `edge_alpha` (body `border`)                                                       |
| hover tracking (`hovered`, cursor)     | the consumer's own zone (`hit.hover`, `cursor: pointer`)                                                  |
| `uniformCapsuleHeight`                 | `h: capsule.height` default; the caller passes the design height the widget wants                         |
| per-monitor `Theme.scale(screen)`      | `scale` parameter, default `ui`, or `scaleNow` §3.2                                                       |
| `implicitWidth` from content           | not ported: `w` is required and the caller measures its content (text publishes `measure:`)               |

Signature (frozen; `lib/capsule.plm` as written):

```plm
component Capsule(w: number,
                  h: number = capsule.height,
                  fill: color = slate,
                  alpha: number = veil,
                  pad: number = capsule.pad,
                  pad_y: number = capsule.pad.y,
                  gap: number = capsule.gap,
                  radius: number = corner,
                  rim: number = 0,
                  edge: number = capsule.edge,
                  edge_tone: color = capsule.edge.tone,
                  edge_alpha: number = capsule.edge.soft,
                  shadow: number = 0,
                  shadow_tone: color = coal,
                  scale: number = ui)
```

| parameter                         | meaning                                      | default               | QS source                                                     |
| --------------------------------- | -------------------------------------------- | --------------------- | ------------------------------------------------------------- |
| `w`                               | design width; the copy is `w * scale` wide   | required              | —                                                             |
| `h`                               | design height                                | `capsule.height` = 18 | `uniformCapsuleHeight` (inner 10 + 2 × pad)                   |
| `fill`                            | box colour                                   | `slate`               | `Theme.surfaceVariant` / `WidgetBg` fallback                  |
| `alpha`                           | how much of `fill` covers                    | `veil` = 53%          | `Theme.surface` #88000000                                     |
| `pad`, `pad_y`                    | room around the content                      | 4 / 2                 | `CapsuleMetrics.padding`, vertical ×0.6                       |
| `gap`                             | gap between several children in the slot     | 2                     | `CapsuleButton.iconSpacing`                                   |
| `radius`                          | corner                                       | 6                     | `shape.cornerRadiusSmall`                                     |
| `rim`                             | 0–1, light inside the silhouette             | 0                     | not in QS; the pleamar rim                                    |
| `edge`, `edge_tone`, `edge_alpha` | hairline outline                             | 0 / `coal` / 8%       | `panel.capsule.borderWidth` / `borderColor` / `borderOpacity` |
| `shadow`, `shadow_tone`           | 0–1 alpha of `0, 2, 6` drop shadow           | 0 / `coal`            | QS cards' shadow                                              |
| `scale`                           | per-copy multiplier, applied to every length | `ui`                  | `Theme.scale(screen)`                                         |

Behaviour and rules:

- The content slot is a horizontal `row`, vertically centred. The caller's children go there in
  order; a widget that stacks content passes a single `column` as the only child
  (`Capsule(120, 40) { column { … } }`). Children accept `show:` as anywhere else.
- All lengths — `w` and `h` included — are design pixels and the capsule multiplies them by `scale`:
  never pass `w * scale`.
- Keep `pad < w / 2` and `pad_y < h / 2`; negative inner sizes are a scene bug.
- `rim` and body `rim:` accept only a literal-led expression; the capsule already writes
  `rim: 1 * rim`, so a fraction (`rim: 0.06`) is what a caller passes.
- Do not scale `alpha` or `shadow` by `scale` — they are alpha, not lengths.
- A widget whose capsule must react to the pointer declares its zone **after** the capsule
  (`zone box hit`), because the later zone is on top; from there `hit.hover` and `hit.pressed` are
  the QS hover/press springs (140 ms each, provided by the language).
- A capsule that holds an icon and a label in the QS way is a `Capsule` with a `row` of an `image`
  (or `figure`) and a `text` inside; `CenteredCapsuleRow.qml` needs no separate pleamar component —
  the row slot is centred by construction.
- Capsules that must be legible over a bright wallpaper take QS's glyph shadow: text `shadow:` (the
  text property) or a scene-level `GlyphShadow`-style rule; the capsule does not add one.

Worked example (this exact scene passes `--check`):

```plm
import "../../lib/palette.plm"
import "../../lib/capsule.plm"

scene Clock {
    surface { size: full, 48 * ui; anchor: bottom; screens: each }
    permissions { services: "clock" }
    service clock { time: text = "--:--"; date: text }

    // scaleNow: a component's default is read where the component is used, so
    // inside `screens: each` this value is per monitor (INTERFACES.md §3.2).
    component ClockCapsule(scale: number = ui * clamp(min(screen.width / design.width, screen.height / design.height), fit.min, fit.max)) {
        size: 84 * scale, 20 * scale
        Capsule(84, 20, fill: slate, alpha: veil, rim: 0.05, scale: scale) {
            text clock.time { at: 42 * scale, 10 * scale; anchor: center; size: 12 * scale; weight: 1 * weight.medium; color: ink }
        }
        zone box hit {
            from: 0, 0; size: 84 * scale, 20 * scale; corner: 10 * scale
            cursor: pointer; label: "Clock {clock.time}"; role: region
        }
    }

    ClockCapsule()
}
```

Two traps the example avoids, both compiler behaviour in 0.4.11:

- **Never forward `children` into a nested component copy.** A scene-local component whose block is
  `Capsule(…) { children }` makes the 0.4.11 compiler overflow its stack
  (`fatal runtime error: stack overflow`). A wrapper component must declare the content it wraps, or
  the call site uses `Capsule(…) { … }` directly. This was verified with `--check` on both forms.
- **`text`'s `size:` and `weight:` and the body's `rim:` need a literal first.** `size: type.small`
  and `weight: weight.medium` are rejected (`expected a number here`); `size: 1 * type.small` and
  `weight: 1 * weight.medium` are accepted. All other numeric properties take bare names
  (`size: corner, 2` on a box is fine).

## 5. Menu and icon APIs (frozen, `lib/menu.plm` / `lib/icons.plm` not written yet)

`lib/menu.plm` and `lib/icons.plm` are the next two files of `lib/`; PH2-B needs the menu rows and
PH2-A the icon names, so their surface is frozen here. Whoever writes them adds them to `lib/` and
keeps these signatures; a change to a signature is an interface change and comes back to this
document first.

### 5.1 Menu rows

```plm
// lib/menu.plm — imports lib/palette.plm
component Action(label: text, press: event, value: number = -1, depth: number = 0,
                 checked: bool = false, danger: bool = false, enabled: bool = true,
                 width: number = menu.width, scale: number = ui)

component Icon(label: text, icon: image, press: event, value: number = -1, depth: number = 0,
               checked: bool = false, danger: bool = false, enabled: bool = true,
               width: number = menu.width, scale: number = ui)
```

- Both draw one row: `width × menu.item.height` design px, `corner: menu.item.corner`, label at
  `menu.pad + depth * menu.sub.gap`, size `type.small * menu.type` (literal first:
  `1 * type.small * menu.type`), one line, ellipsis. `Icon` puts the icon (`menu.icon` square)
  before the label.
- Hover wash under the pointer: `mix(slate, ink, 0.2 * hit.hover)`; pressed adds `hit.pressed`. The
  zone is inside the component (`role: item`, `label:` from the parameter, `selected: checked`,
  `active: enabled`) and the press **emits the event passed in**, with the row's `value` as payload:
  `on press hit { emit press(value) }`. A scene therefore declares one event and reads the choice:
  `event pick`, `on pick(v)`.
- `danger: true` paints the label `warn`; `enabled: false` paints it `ink.off`, dims the row and
  leaves the zone inactive (described as inactive, not pressable).
- `checked: true` draws the check mark at the right edge (`menu.chevron`-sized `path`); a submenu
  row draws a chevron instead. Both are the implementation's business, the parameters are the
  interface.
- **Menus are drawn in place (D7), never in a `popup`.** A menu panel is a
  `Capsule(width, height, radius: menu.corner, fill: coal, alpha: 1, scale: scale)` with a
  `column { pad: menu.pad; gap: menu.item.gap; … }` of rows inside; a scene that must hold more rows
  than fit declares the panel with a `view:` and lets the list scroll. The QS/`libdbusmenu` shapes
  are the model the rows are fed from:

```lua
-- tray menu from the service, straight into a model (see --docs logic)
-- record: { id, label, enabled, separator, checked, children }
local menu = sys.ask("tray.menu", key)
model.rows = menu
```

- A row record with a submenu is walked with a nested `for`; `depth:` shifts the label so the tree
  reads. `separator` records draw a hairline instead of a row (implementation detail; the parameter
  surface is the record, not a component).
- Tray menus: pleamar's `tray` service caps a menu at 14 rows and has no tooltips (D7); the port
  accepts both limits and documents them as deviations.

Call it as `Action(…)` / `Icon(…)` after a plain `import "../../lib/menu.plm"`, or `menu.Action(…)`
after `import "../../lib/menu.plm" as menu` when another import also has an `Action`. A scene that
has no `Action` of its own should import with the surname once `lib/menu.plm` is used by more than
one library.

### 5.2 `lib/menu.plm` usage example (compiles against the same palette)

```plm
import "../../lib/palette.plm"
import "../../lib/menu.plm" as menu

scene Menu {
    surface { size: 240, 160; anchor: center }
    event pick
    image wifi = icon "network-wireless", 16, 16

    Capsule(menu.width, 3 * menu.item.height + 4 * menu.pad, radius: menu.corner, fill: coal, alpha: 1) {
        column { gap: menu.item.gap
            menu.Action("Open", pick, value: 0)
            menu.Icon("Wi-Fi", wifi, pick, value: 1, checked: true)
            menu.Action("Power off", pick, value: 9, danger: true)
        }
    }
}
```

### 5.3 Icons (`lib/icons.plm`, frozen names)

`lib/icons.plm` declares shared `image`s so every scene uses the same glyph and cell shape. Names,
in the QS material vocabulary translated to the shell's words:

`wifi`, `wifi.off`, `ethernet`, `vpn`, `bluetooth`, `bluetooth.on`, `battery`, `battery.charging`,
`volume`, `volume.muted`, `microphone`, `microphone.muted`, `clock`, `weather`, `keyboard`, `tray`,
`media`, `media.play`, `media.pause`, `media.previous`, `media.next`, `power`, `lock`, `search`,
`close`, `check`, `chevron`, `workspace`.

Each is declared for its role's size (`media`, `wifi`, … at `icon.small`; the big launcher and lock
marks at `icon.large`), and each `file`/`icon` source must render in the smoke PNG before it lands —
the icon theme in the session is not guaranteed to have a glyph name, so the writer verifies by
screenshot, not by the name existing in a list. Scenes that need an icon no declaration covers
declare it locally; `lib/icons.plm` stays small.

## 6. Per-scene settings (JSON under `~/.local/share/pleamar/<scene>/`)

### 6.1 Where and how

- One file per scene: `~/.local/share/pleamar/<scene>/settings.json`. A scene with several
  independent feature groups may add one file per group in the same folder (`media.json`,
  `weather.json`, `calendar.json`); the file name is the group's.
- The folder is the scene's own folder and the only one it can touch: pass bare names to
  `files.read` / `files.write`, never a path, never `..`. The path for a human is
  `~/.local/share/pleamar/<scene>/settings.json` (`XDG_DATA_HOME`); the module deployment creates
  the folder.
- The scene's logic is the only writer. It reads at start, applies defaults, clamps, and writes back
  on user action. Reads never write; a missing file is the defaults; a broken file logs its error
  (pleamar reports the place) and keeps the defaults; the next user action rewrites it.
- **Unknown keys survive.** Never write a table built from scratch: mutate the table that was read
  (`raw[key] = value`) so keys another version (or another feature) put there stay in the file.
- Changes from outside (an editor, a second copy) are honoured live via
  `sys.watch("files:" .. FILE, …)`; the watcher re-applies the same defaults/clamps.
- `files.write` is all-or-nothing (temp file then rename); never open-write the file in any other
  way (there is none, by design).

Canonical logic shape (Luau, sandbox-safe; `math.clamp` exists in Luau but the explicit helper also
clamps NaN away):

```lua
-- settings.luau for the `bar` scene.
local FILE = "settings.json"

-- Defaults live in code. The file holds only what the user changed.
local D = {
    edge = "bottom",        -- bottom on trantor (see the plan), top allowed
    height = 22,            -- design px, bar.height
    fontScale = 1.0,        -- multiplies type.scale
    animations = true,
}

local function num(v, lo, hi, def)
    if type(v) ~= "number" or v ~= v then return def end
    return math.max(lo, math.min(hi, v))
end

local raw = {}
local ok, got = pcall(function() return sys.ask("files.read", FILE, "json") end)
if ok and type(got) == "table" then raw = got end

local function apply()
    local edge = raw.edge
    if edge ~= "top" and edge ~= "bottom" then edge = D.edge end
    fact.edge = edge                                      -- fact edge: top | bottom
    fact.height = num(raw.height, 16, 64, D.height)
    fact.fontScale = num(raw.fontScale, 0.5, 2.0, D.fontScale)
    fact.animations = (raw.animations ~= false)
end
apply()

-- Another copy or an editor changed it.
sys.watch("files:" .. FILE, function() apply() end)

-- The user picked something: keep every other key that was in the file.
local function save(key, value)
    raw[key] = value
    sys.call("files.write", FILE, raw)
end
```

### 6.2 Common keys (every scene that has them uses these names and clamps)

| key             | type             | default     | clamp          | meaning                                                                                                                |
| --------------- | ---------------- | ----------- | -------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `scale`         | number           | 1.0         | 0.5 – 2.0      | user multiplier applied on top of `ui` and the per-monitor fit                                                         |
| `fontScale`     | number           | 1.0         | 0.5 – 2.0      | multiplies `type.scale` (the QS `fontSizeMultiplier`)                                                                  |
| `fontFamily`    | text             | `"Iosevka"` | non-empty      | written into `family:` until pleamar gets string lets                                                                  |
| `animations`    | bool             | true        | —              | false = settle springs at once (QS `animationsEnabled`; `--reduced-motion` does this too)                              |
| `reducedMotion` | bool             | false       | —              | the QS Settings.json name for the same intent; `animations` is the pleamar name, keep one per scene and document which |
| `monitorScale`  | array of numbers | `[]`        | each 0.5 – 2.5 | optional per-monitor override indexed by `screen.index`; only for scenes that declare a per-monitor model              |

Rules that make these safe:

- A value of the wrong type is **ignored, not fatal**: `tonumber` for numbers, `type(v) == "table"`
  for arrays, the default otherwise. Log once (`log("settings: height ignored")`) so the bad file is
  findable.
- Numbers are clamped after conversion and NaN is rejected; strings are checked against their
  allowed set (`edge == "top" or edge == "bottom"`), never blindly trusted.
- Arrays are truncated to the scene's cap (a widgets list to 24 entries, say) so a huge file cannot
  blow the model's `max`.
- Settings are not a channel between scenes: they are user preferences. Cross-scene signalling goes
  through the cache files of §1.2.

### 6.3 Per-scene keys (the keys other tools may rely on)

| scene           | key               | type          | default              | clamp                    | meaning                                |
| --------------- | ----------------- | ------------- | -------------------- | ------------------------ | -------------------------------------- |
| `bar`           | `edge`            | text          | `"bottom"`           | `top`/`bottom`           | the strip's anchor                     |
| `bar`           | `height`          | number        | 22                   | 16 – 64                  | strip height, design px                |
| `bar`           | `widgets`         | array of text | the QS default order | ≤ 24                     | visible widgets, in reading order      |
| `bar`           | `startupClean`    | bool          | true                 | —                        | the login gate (QS startup-clean bar)  |
| `panels`        | `closeOnEscape`   | bool          | true                 | —                        | Escape closes the open drawer          |
| `panels`        | `closeOnOutside`  | bool          | true                 | —                        | a press outside closes the open drawer |
| `notifications` | `dnd`             | bool          | false                | —                        | do not disturb (also a fact, §2.1)     |
| `notifications` | `maxToasts`       | number        | 2                    | 1 – 6                    | stacked toasts                         |
| `notifications` | `autoDismissMs`   | number        | 6000                 | 0 – 60000                | 0 = keep until dismissed               |
| `notifications` | `historyMax`      | number        | 50                   | 0 – 200                  | history entries kept across restarts   |
| `toast`         | `anchor`          | text          | `"top_right"`        | a `surface.anchor` value | where toasts stack                     |
| `toast`         | `margin`          | number        | 12                   | 0 – 64                   | design px from the corner              |
| `overlay`       | `dismissOnEscape` | bool          | true                 | —                        | Escape closes overlays                 |
| `lock`          | `clock24h`        | bool          | true                 | —                        | greeter `nixie24h`                     |
| `lock`          | `uiScale`         | number        | 1.2                  | 0.8 – 2.0                | greeter `uiScale`                      |
| `launcher`      | `maxResults`      | number        | 8                    | 1 – 20                   | list cap                               |
| `theme`         | `wallpaper`       | text          | `""`                 | —                        | the wallpaper the theme was built from |

A scene documents its own extra keys in its file header as `key (type, default, clamp)` and adds a
row here only when another scene, a script or a test reads it. A key that is dropped in the port is
listed in the migration note, not silently ignored.

## 7. Helper-worker protocol (PH2-E)

Missing services are filled with small worker programs, not with new pleamar features (D4). The
protocol between a scene's logic and a worker is frozen here:

**Transport.** The worker is an executable the scene's logic starts with
`spawn(name, args, on_line, on_exit, { stdin = "open" })`. Its **stdout is one JSON object per
line** (JSON Lines, UTF-8, `\n` terminated, no embedded newlines); its stdin is the same, written
with `write(id, line .. "\n")`. `stderr` is for humans only (a traceback a journal sees) and is
never part of the protocol. Logs on stdout are a defect: a line that does not parse is reported as a
protocol error and the sample is dropped.

**Names and permissions.** Workers live in `files/pleamar/scripts/helpers/` (PH2-E scope), are
installed into `PATH` as `pleamar-<name>` (`pleamar-sysmon`, `pleamar-weather`, `pleamar-calendar`,
`pleamar-kbdlayout`, `pleamar-palette`, `pleamar-netdetail`, `pleamar-btdetail`), and are spawned by
that bare name. A scene declares only the ones it uses: `permissions { run: "pleamar-sysmon" }`.
Never `sh -c`, never a path, never a second worker name the module does not install.

**Lifecycle.** One worker per view that needs it, started when the view opens and killed when it
closes:

- start with `{ stdin = "open" }`, then send the subscriptions;
- `write(id, '{"cmd":"stop"}\n')` or `write(id)` (close) asks it to finish; `kill(id, "term")` is
  the hard stop; `kill(id)` forgets the handle;
- the platform stops everything the logic started on logic reload and on scene exit; the worker must
  not daemonise, fork into the background or outlive its stdin;
- `on_exit(_, code)` in the scene restarts on failure with a backoff (1 s, 2 s, 5 s, then stop and
  set the error fact) and marks the last sample stale; a clean `code == 0` after `stop` is not an
  error.

**Handshake.** The first line the worker writes is:

```json
{"ok":true,"worker":"sysmon","version":1,"topics":["cpu","mem","net","disk"]}
```

A scene that does not know `version` kills the worker and reports it; version 1 is this document. A
worker that cannot start writes `{"ok":false,"worker":"sysmon","err":"…"}` and exits non-zero.

**Scene → worker commands** (one object per line; `cmd` is required):

| line                                                   | meaning                                       |
| ------------------------------------------------------ | --------------------------------------------- |
| `{"cmd":"sample"}`                                     | emit one sample of every subscribed topic now |
| `{"cmd":"subscribe","topic":"cpu","interval_ms":1000}` | start a topic, one line per `interval_ms`     |
| `{"cmd":"unsubscribe","topic":"cpu"}`                  | stop that topic                               |
| `{"cmd":"set","interval_ms":250}`                      | change the cadence of the subscribed topics   |
| `{"cmd":"stop"}`                                       | finish cleanly, exit 0                        |

Every command gets an acknowledgement line `{"ok":true,"ack":"subscribe"}` or an error line
`{"ok":false,"err":"unknown topic: cpu2"}`. An unknown `cmd` is an error line, not an exit.

**Worker → scene lines.**

- sample:
  `{"ok":true,"worker":"sysmon","topic":"cpu","t":1730000000123,"data":{"load":0.31,"cores":16}}` —
  `t` is milliseconds since the epoch, `data` is an object whose fields map 1:1 onto the scene's
  model fields (the logic hands `data` to a model exactly as it comes, per `--docs logic` §"Lists
  that come from data");
- error: `{"ok":false,"worker":"weather","err":"open-meteo: HTTP 503","t":…}` — errors surface in
  the scene as a text/fact (`worker.err`) and the last good sample stays;
- nothing else. No progress bars, no multi-line JSON, no empty lines.

**Budget and cadence.** One line per sample, never more than 10 lines a second by default
(`interval_ms` ≥ 100); a line is at most 64 KiB; a worker that has nothing new to say still emits
one sample per interval (a heartbeat is how the scene knows the worker is alive) or, if the scene
asked for `change`-only, an explicit `{"ok":true,…,"data":{}}` keepalive at most every 10 intervals.
A slow consumer causes drops, never unbounded buffering: the scene keeps the newest line.

Scene-side client skeleton (this is the pattern PH2-E verifies; the worker side is a script with the
same lines):

```lua
local id
local function on_line(line)
    local ok, msg = pcall(json.decode, line)
    if not ok or type(msg) ~= "table" then
        fact.worker.err = "sysmon: bad line"
        return
    end
    if msg.ok then
        model.cpu = msg.data          -- the model's fields are the data's fields
        fact.worker.err = ""
    else
        fact.worker.err = tostring(msg.err)
    end
end
local function on_exit(_, code)
    id = nil
    if code ~= 0 then fact.worker.err = "sysmon: exit " .. tostring(code) end
    after(2000, start)                 -- backoff; give up after three tries
end
local function start()
    id = spawn("pleamar-sysmon", {}, on_line, on_exit, { stdin = "open" })
    write(id, '{"cmd":"subscribe","topic":"cpu","interval_ms":1000}\n')
end
start()
```

Closing the view: `if id then kill(id, "term") end`. PH2-E proves no worker survives its view
(`pgrep -f pleamar-sysmon` empty after close) and that `--check` of every scene that spawns one
lists the permission.

## 8. Labels, roles and the agent policy

The shell is driven by `pleamar --say <scene> describe` and by a hand that presses by name. An agent
must be able to read every widget and must not be able to hurt the user. The rules below are the
interface; PH2's verification (describe snapshots) checks them.

### 8.1 The rules

1. **Every interactive zone and field carries `label:`.** A label is a text with holes
   (`label: "Volume {volume * 100, 0} %"`), a live text, or `pick(k, "Volume", "Microphone")` inside
   a copy. It is the human name of the thing and the name `--say press …` uses. A zone that can be
   pressed and says nothing is a defect (the runtime logs one).
1. **Labels are unique inside a surface** whenever the UI allows it. Repeated rows put their
   identity in the label: `label: "Dismiss {n.app}: {n.title}"`, not `label: "Dismiss"`. When two
   zones share a label, `press <label>` is ambiguous and the interface cannot be automated.
1. **`role:` says what it is**, explicitly on every zone whose rules do not make it obvious:
   `button`, `toggle`, `slider`, `tab`, `link`, `item`, `list`, `region`. `region` is for a
   surface-wide catcher or a read-only hover area. Together with `value:`, `checked:` and
   `selected:` it is the whole machine-readable description; a slider without `value:` is a defect.
1. **A zone that is not interactive gets no label and is not declared `zone`.** Plain drawing stays
   out of `describe`; only what a hand could touch is described.
1. **`agent: no` on everything destructive.** Destructive means: it ends or locks the session,
   closes a window or application, forgets a network or a device, empties a history or a clipboard,
   or discards unsaved work. The full list for this shell: power off, reboot, log out, suspend, lock
   now, close window (`window.close`), close all notifications / clear history, forget network,
   forget Bluetooth device, unmount or eject a disk, launch-a-program-with-arguments that installs
   something. An agent still *sees* these zones in `describe`; it cannot press them. A human must be
   able to do them in two steps: first press arms (`fact armed = true`), second press within five
   seconds acts, or the press is a `hold … for 600ms`; the arming press is also `agent: no`, so the
   whole road is closed to an agent.
1. **`agent: hidden` on everything private.** The lock surface is hidden as a whole
   (`surface { … agent: hidden; captures: hidden }`); password and secret fields are hidden
   (`secret: true` plus `agent: no`); a zone whose label would leak private content (a clipboard
   preview, a notification body, a file name in a password manager) is hidden. Hidden means “not in
   `describe` at all”: no name, no box, no text. When in doubt between `no` and `hidden`, choose
   `no` — invisible zones make the UI harder to explain; only privacy earns `hidden`.
1. **A field that holds a password is `secret: true` and `agent: no`.** The lock scene's password
   input is both; agents never get its text.
1. Labels are translated like any other text (`translations`), so write them as full sentences or
   nouns, not as keys. Tooltips reuse the label unless the tooltip says more.

### 8.2 The standard labels of this shell

Use these texts verbatim; tests match them and the migration keeps them stable.

| zone                 | label                                              | role     | state                                | agent                 |
| -------------------- | -------------------------------------------------- | -------- | ------------------------------------ | --------------------- |
| clock                | `Clock {now.time}`                                 | `region` | —                                    | —                     |
| workspace tab        | `Workspace {ws.name}`                              | `tab`    | `selected: ws.active`                | —                     |
| volume               | `Volume {audio.volume * 100, 0} %`                 | `slider` | `value: "{audio.volume * 100, 0} %"` | —                     |
| microphone           | `Microphone {audio.input * 100, 0} %`              | `slider` | `value: "{…} %"`                     | —                     |
| brightness           | `Brightness {brightness.level * 100, 0} %`         | `slider` | `value: "{…} %"`                     | —                     |
| network              | `Network {network.name}` / `Network: offline`      | `button` | —                                    | —                     |
| VPN                  | `VPN: {state}`                                     | `button` | —                                    | —                     |
| Bluetooth            | `Bluetooth`                                        | `button` | —                                    | —                     |
| battery              | `Battery {battery.percent, 0} %`                   | `button` | —                                    | —                     |
| keyboard layout      | `Keyboard: {layout}`                               | `button` | —                                    | —                     |
| media capsule        | `Media: {media.title}` / `Media`                   | `button` | —                                    | —                     |
| transport            | `Previous track` / `Play` / `Pause` / `Next track` | `button` | —                                    | —                     |
| weather              | `Weather: {temp, 0}°, {condition}`                 | `button` | —                                    | —                     |
| system monitor       | `System monitor`                                   | `button` | —                                    | —                     |
| tray item            | `{tray.title}` (fall back to the app name)         | `button` | —                                    | —                     |
| drawer opener        | the drawer title, §2.2                             | `button` | —                                    | —                     |
| drawer close         | `Close {drawer}`                                   | `button` | —                                    | —                     |
| power: lock          | `Lock`                                             | `button` | —                                    | —                     |
| power: suspend       | `Suspend`                                          | `button` | —                                    | —                     |
| power: log out       | `Log out`                                          | `button` | —                                    | `no`                  |
| power: reboot        | `Reboot`                                           | `button` | —                                    | `no`                  |
| power: power off     | `Power off`                                        | `button` | —                                    | `no`                  |
| toast                | `{n.app}: {n.title}`                               | `item`   | —                                    | —                     |
| toast notice actions | `{action.label}`                                   | `button` | —                                    | —                     |
| toast dismiss        | `Dismiss notification`                             | `button` | —                                    | —                     |
| notification centre  | `Notifications`                                    | `list`   | —                                    | —                     |
| centre entry         | `{n.app}: {n.title}`                               | `item`   | —                                    | —                     |
| centre clear         | `Clear all notifications`                          | `button` | —                                    | `no`                  |
| overlay catcher      | `Dismiss overlay`                                  | `region` | —                                    | `no`                  |
| lock password        | `Password`                                         | field    | —                                    | `no` + `secret: true` |
| lock unlock          | `Unlock`                                           | `button` | —                                    | `no`                  |
| launcher input       | `Search applications`                              | field    | —                                    | —                     |
| launcher result      | `{app.local_name}`                                 | `item`   | —                                    | —                     |

`—` in the agent column means the default. The default for a zone that only navigates or changes a
preference is `agent: yes` (pressable); the default for `agent:` is what the surface says, and the
surface default is yes.

## 9. Verification and compiler notes

### 9.1 Gates

- After every edit: `env -u LD_LIBRARY_PATH /tmp/plm-recon/result/bin/pleamar --check <scene>.plm`
  (or `pleamar --check` when the binary is in `PATH`). The compiler is the only authority on syntax;
  a scene that merely starts is not checked enough.
- Before handoff: `just pleamar-check` (runs `scripts/dev/check-plm.sh` over every tracked `.plm`)
  and `just lint`. While the binary is not in `PATH` the gate prints a skip notice and exits 0;
  never mistake the skip for a pass.
- **Known gate defect (reported to the integrator, not fixed here):** `check-plm.sh` compiles every
  `.plm` including `lib/*.plm`, and `--check` refuses a library file, so with the binary in `PATH`
  it ends `FAILED: 2 of 3 scene(s)`. A failure on `lib/*.plm` is this defect, not a scene error; the
  gate must skip library files (or be given the consumer scenes to check them through).
- A library file cannot be checked alone: the compiler answers `this is a library: it is not opened`
  (exit 1) for `lib/*.plm`. Check libraries through a consumer scene; keep the consumer in `/tmp`,
  never in the repo, and let it import the library by relative path
  (`import "../../etc/nixos/files/pleamar/lib/palette.plm"` from `/tmp/dm-consumer/`). The PH1
  consumers are in `/tmp/plm-consumer/` (`palette_probe.plm` exercises every let and spring,
  `capsule_use.plm` every capsule parameter).
- Per scene, before a task is done: headless PNG reviewed, `describe` snapshot committed under
  `tests/`, budget row in `tests/evidence/` (harness owned by PH0-T3/PH0-T4).
- The behavior of a runtime change is not proven by `--check`; it is proven by a headless run plus a
  `describe` snapshot. Say which was run.

### 9.2 Compiler notes for 0.4.11 (verified, not folklore)

These were found while writing the two libraries; they are the traps that cost time.

1. **Library check refuses by design** — see 9.1.
1. **Literal first.** The `size:` and `weight:` properties of `text` and the `rim:` property of
   `body` reject an expression that starts with a name (`size: type.small`, `weight: weight.medium`,
   `rim: rim` all fail with `expected a number here`). Write `size: 1 * type.small`,
   `weight: 1 * weight.medium`, `rim: 1 * rim`. Every other numeric property takes bare names
   (`size: corner, 2` on a box is fine).
1. **Colour literals are opaque:** `#rgb` or `#rrggbb`, nothing else. Translucency is a tone plus an
   alpha number applied with `opacity:` / `fill: tone alpha`; there is no 8-digit hex and no
   colour-with-alpha function.
1. **No string `let`s.** `let font = "Iosevka"` is rejected; the family is written at each `text`
   (`family: "Iosevka"`) and the rest of the string tokens live in settings JSON.
1. **A parameter default cannot name another parameter** (`h: number = 18 * s` fails where `s` is a
   sibling). It may name outer/library lets, and it is read at the use site — that is what makes
   `scale` defaults (§4) per monitor.
1. **`role:` cannot be passed as a `text` parameter**, and `agent:` cannot be parameterised either;
   a component that owns a zone hardcodes its role. Scenes that need a different role declare their
   own zone.
1. **Do not forward `children` into a nested component copy.** A scene component whose block is
   `Capsule(…) { children }` makes the compiler overflow its stack
   (`fatal runtime error: stack overflow`, exit 134). Declare the wrapped content in the wrapper, or
   call `Capsule` at the use site.
1. **A `let` declared twice across imports is allowed with a warning** — and the warning is a real
   hazard: `in a scene copied per monitor each copy may take one or the other`. That is why
   `theme.plm` must not redeclare palette names (§1.4).
1. **A loose `let` is shared by the copies of a scene, and a group does not keep its `let`s.** Every
   per-monitor value is written in the repeated drawing (§3.2).
1. **Rules cannot run programs and cannot log.** `run`, `spawn`, `log` and `sys.*` belong to the
   `.luau` logic; a rule only changes facts, emits events and commands services.
1. **A `text` inside a `group` needs its own `at:`;** inside a `row`/`column` it is placed by the
   layout. The capsule slot is a `row`, which is why capsule content needs no `at`.
1. **`--record` marks component copies** (`px#Hat2`); the `describe` names are the labels, not the
   internal names.

### 9.3 Change control

An interface change is: a palette name, a capsule/menu/icon signature, a scene or drawer name, a
fact in §2.1, a settings key, the helper protocol, a standard label or the agent policy. Change it
here first, run every consumer, and announce it where the PH2 writers read (the parent agent's
report). Adding a palette token is not an interface change if the name is new; renaming or
re-meaning an existing one is.
