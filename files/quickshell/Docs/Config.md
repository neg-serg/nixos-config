Quickshell Configuration: Settings.json and Theme/.theme.json options

Locations

- `~/.config/quickshell/Settings.json`: behavioral and global settings.
- `~/.config/quickshell/Theme/.theme.json`: generated theme tokens (colors, sizes, animation, etc.).
  Edit the source files under `Theme/*.jsonc` (merge order defined in `Theme/manifest.json`).
  Quickshell watches that directory and rewrites `.theme.json` automatically; use
  `node Tools/build-theme.mjs` only when you need a manual rebuild outside a running session.
- Base directory is `${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/`. Files are created on first run
  with defaults.

Format

- Settings.json is plain JSON. Theme parts use JSONC (comments allowed) and compile down to
  `Theme/.theme.json`, which remains strict JSON for Quickshell.

Settings.json (all options)

General

- weatherCity: string, default "Moscow". City used by the weather widget.
- userAgent: string, default "NegPanel". HTTP User‑Agent; include app name and contact if possible.
- debugLogs: boolean, default false. Enables low‑importance debug logs.
- debugNetwork: boolean, default false. Extra logging for network layer.
- strictThemeTokens: boolean, default false. Strict warnings for missing/deprecated Theme tokens
  (see ThemeTokens.md).

Date & Time

- use12HourClock: boolean, default false. 12‑hour time in the bar.
- reverseDayMonth: boolean, default false. Flip day and month order in date.
- useFahrenheit: boolean, default false. Use °F for temperatures.

UI & Typography

- fontSizeMultiplier: number, default 1.0. Global font multiplier (e.g. 1.2 = +20%).

Bar/Widgets

- showMediaInBar: boolean, default false. Show the media block in the bar.
- showWeatherInBar: boolean, default false. Show weather button in the bar.
- showVolumeOnHover: boolean, default true. Show the audio level (volume %, mic level, Genelec dB)
  when the cursor hovers the capsule — delayed reveal via the existing pill/tooltip timers.
- collapseSystemTray: boolean, default true. Collapse tray icons.
- collapsedTrayIcon: string, default "expand_more". Icon when tray is collapsed (Material icon
  name).
- trayFallbackIcon: string, default "broken_image". Fallback tray icon name.

Startup gate (the bar at login)

- startupCleanBar: boolean, default true. At login the bar shows only the widgets listed in
  startupCleanWidgets and hides the rest, so the first thing on screen is the wallpaper, the clock
  and the weather. The first real window brings the full bar back, and it then stays normal for the
  rest of the session. The gate arms only when the panel starts together with the session (the login
  marker in `$QS_LOGIN_STATE_DIR` has to be fresh), so a panel restarted in the middle of work —
  `systemctl --user restart quickshell`, a Hyprland config reload — never strips the bar.
- startupCleanWidgets: string array, default ["clock", "weather"]. Widget identifiers that survive
  the login view; they still obey panelLayout and their own conditions (e.g. showWeatherInBar).
- startupCleanMinMs: number, default 10000. How long the clean look is held once the panel is up,
  counted from panel start. Without the dwell the autostart burst (kitty term, telegram, …) would
  map a window within a second and the bar would be back to normal before it finished sliding in.
- startupCleanIgnoreSpecial: boolean, default true. Ignore windows on special workspaces (the
  scratchpads pre-launched at login) and hidden daemon windows (`nicotine -s`) when deciding whether
  "the first window" has appeared. Turn it off to count every window, including those.

Previewing the look without logging out: `QS_STARTUP_CLEAN=1` holds the gate up for as long as the
panel runs (restart the panel to leave it), `QS_STARTUP_CLEAN=0` disables the gate outright.

Monitors & Scaling

- barMonitors: string array, default []. Which monitors show the bar (optional; otherwise
  automatic).
- monitorScaleOverrides: object { "ScreenName": number }, default {}. Per‑monitor UI scale keyed by
  `Screen.name`.

Media

- timeBracketStyle: string, default "round". Brackets for RichText:
  round|square|lenticular|lenticular_black|angle|tortoise.
- musicPopupProgressHeight: number, default 3. Progress scrub-bar thickness in logical px (scaled).

The audio spectrum analysers (CAVA-based: bar capsule, media toast, music panel) and their
`cava*`/`spectrum*`/`*Analyser*` settings were removed on 2026-10-17 together with the `cava`
package: the bars were the only consumer of that stream, and the panel spent ~9% of a core
sampling it.

Music Players

- pinnedPlayers: string array, default []. Pinned players (priority).
- ignoredPlayers: string array, default []. Players to ignore.
- lastActivePlayers: **Moved to ~/.cache/quickshell/state.json** (runtime state, not committed to
  git).
- playerSelectionPriority: string array, default
  ["mpdPlaying","anyPlaying","mpdRecent","recent","manual","first"]. Selection algorithm priority.
- playerSelectionPreset: string, default "default". Preset name for priority ordering.

Media side panel popup

- musicPopupWidth: integer, default 840. Width (logical px; scaled per monitor).
- musicPopupHeight: integer, default 250. Height (logical px; used when content doesn’t define
  height).
- musicPopupPadding: integer, default 12. Inner padding (logical px).
- musicPopupEdgeMargin: integer, default 4. Horizontal margin between popup and screen edge (logical
  px; scaled per monitor).

Contrast & Accessibility

- contrastThreshold: number, default 0.5. Threshold for light/dark text selection against
  backgrounds.
- contrastWarnRatio: number, default 4.5. Target contrast ratio for warnings.

Network

- networkPingIntervalMs: integer, default 30000. Network/ping refresh interval.
- networkNoInternetColor: color string, default "#FF6E00". No‑internet status color.
- networkNoLinkColor: color string, default "#D81B60". No‑link status color.

Weather

- showWeatherInBar: boolean, default false. Weather button in bar.
- useFahrenheit: boolean, default false. Show °F.
- weatherCity: string. City for current weather and forecast.

Theme/.theme.json (short)

- All typography, colors, paddings, radii, animations, etc. are hierarchical tokens.
- Full list of tokens, types/defaults, and guidance: `Docs/ThemeTokens.md`.
- Up‑to‑date example schema: `Docs/ThemeHierarchical.json`.
- Important groups: `colors.*`, `panel.*`, `shape.*`, `tooltip.*`, `ui.*`, `ws.*`, `timers.*`,
  `network.*`, `media.*`, `calendar.*`, `weather.*`, `vpn.*`, `time.*`, `volume.*`,
  `sidePanel.*`.
- Strict mode (`Settings.settings.strictThemeTokens = true`) logs warnings for missing tokens and
  deprecated flat keys. Flat keys are removed after 2025‑11‑01.

Tools

- Build theme: `node Tools/build-theme.mjs` (merges `Theme/*.jsonc` into `Theme/.theme.json`; add
  `--check` for CI/hooks).
- Validate theme:
  `node Tools/validate-theme.mjs [--theme Theme/.theme.json] [--schema Docs/ThemeHierarchical.json] [--strict]`
  (auto-loads from the `Theme/` parts when present).
- Generate theme schema: `node Tools/generate-theme-schema.mjs` (updates
  `Docs/ThemeHierarchical.json` from the merged theme parts).
- Validate settings:
  `node Tools/validate-settings.mjs [--settings ~/.config/quickshell/Settings.json] [--schema Docs/SettingsSchema.json]`.
- Find settings keys that drifted apart: `node Tools/lint-settings.mjs` — lists keys declared in
  `Settings/Settings.qml` that no code reads (dead tokens) and keys read but never declared (typos;
  non-zero exit). A key counts as used when it appears as `settings.<key>` (the singleton, a helper
  parameter, a re-aliased object) or as a table entry `key: "<key>"` (GlassPanel presets); `Tools/`
  is skipped, while a name mentioned only in a comment still counts as dead.

Settings.json schema and samples

- JSON Schema: `Docs/SettingsSchema.json` (Draft‑07) — types, defaults, and allowed values.
- Preset examples:
  - `Docs/SettingsMinimal.json` — minimal typical overrides.

Tips

- Color values: `#RRGGBB` or `#AARRGGBB`.
- Integers are logical px before per-screen scaling; runtime scales via `Theme.scale(Screen)` and
  per-monitor overrides.
- Unsure about a token? Search for it in `Settings/Theme.qml` and `Docs/ThemeTokens.md`.

Keyboard layout indicator (Hyprland)

- The Bar’s keyboard layout indicator updates instantly from Hyprland’s keyboard-layout events for a
  zero‑lag UI.
- If a Hyprland submap is active, the indicator shows a pictogram for that submap in accent color
  before the layout with a keyboard glyph (e.g., `★ ⌨ en`) so the current mode is visible.
- To avoid noise from pseudo keyboards (power-button, video-bus, virtual keyboards), the module
  identifies the main:true keyboard at init and prefers its events.
- If an event arrives from a non‑main device, the module issues one quick `hyprctl -j devices`
  snapshot to confirm/correct the label. This keeps the common path fast while fixing rare stale
  payloads.
- There are no timers/debounces; snapshots are not performed for every event to avoid latency.
- Click behavior: toggles layout via `hyprctl switchxkblayout current next` (no shell involved).
- Recommended Hyprland binding for speed: `bind = $M4, S, switchxkblayout, current, next`
  (dispatcher syntax, comma‑separated args).
