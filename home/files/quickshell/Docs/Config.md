Quickshell Configuration: Settings.json and Theme/.theme.json options

Locations
- `~/.config/quickshell/Settings.json`: behavioral and global settings.
- `~/.config/quickshell/Theme/.theme.json`: generated theme tokens (colors, sizes, animation, etc.). Edit the source files under `Theme/*.jsonc` (merge order defined in `Theme/manifest.json`). Quickshell watches that directory and rewrites `.theme.json` automatically; use `node Tools/build-theme.mjs` only when you need a manual rebuild outside a running session.
- Base directory is `${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/`. Files are created on first run with defaults.

Format
- Settings.json is plain JSON. Theme parts use JSONC (comments allowed) and compile down to `Theme/.theme.json`, which remains strict JSON for Quickshell.

Settings.json (all options)

General
- weatherCity: string, default "Moscow". City used by the weather widget.
- userAgent: string, default "NegPanel". HTTP User‑Agent; include app name and contact if possible.
- debugLogs: boolean, default false. Enables low‑importance debug logs.
- debugNetwork: boolean, default false. Extra logging for network layer.
- strictThemeTokens: boolean, default false. Strict warnings for missing/deprecated Theme tokens (see ThemeTokens.md).

Date & Time
- use12HourClock: boolean, default false. 12‑hour time in the bar.
- reverseDayMonth: boolean, default false. Flip day and month order in date.
- useFahrenheit: boolean, default false. Use °F for temperatures.

UI & Typography
- dimPanels: boolean, default true. Dim panels appearance.
- fontSizeMultiplier: number, default 1.0. Global font multiplier (e.g. 1.2 = +20%).

Bar/Widgets
- showMediaInBar: boolean, default false. Show the media block in the bar.
- showWeatherInBar: boolean, default false. Show weather button in the bar.
- collapseSystemTray: boolean, default true. Collapse tray icons.
- collapsedTrayIcon: string, default "expand_more". Icon when tray is collapsed (Material icon name).
- trayFallbackIcon: string, default "broken_image". Fallback tray icon name.

Monitors & Scaling
- barMonitors: string array, default []. Which monitors show the bar (optional; otherwise automatic).
- monitorScaleOverrides: object { "ScreenName": number }, default {}. Per‑monitor UI scale keyed by `Screen.name`.

Media & Visualizer
- showMediaVisualizer: boolean, default false. Enable visualizer (spectrum) next to track.
- activeVisualizerProfile: string, default "classic". Active visualizer profile name.
- visualizerProfiles: object of profiles keyed by name. Each profile can override CAVA/spectrum parameters below.
- timeBracketStyle: string, default "round". Brackets for RichText: round|square|lenticular|lenticular_black|angle|tortoise.

CAVA / Spectrum (global defaults; each may be overridden per profile in visualizerProfiles.<name>)
- cavaBars: integer, default 86. Number of bars.
- cavaFramerate: integer, default 24. Frames per second.
- cavaMonstercat: boolean, default false. Monstercat smoothing.
- cavaGravity: integer, default 150000. Gravity/decay constant.
- cavaNoiseReduction: integer, default 12. Noise reduction level.
- spectrumUseGradient: boolean, default false. Gradient fill.
- spectrumMirror: boolean, default false. Mirror spectrum.
- showSpectrumTopHalf: boolean, default false. Show top half only.
- spectrumFillOpacity: number 0..1, default 0.35. Fill opacity.
- spectrumHeightFactor: number, default 1.2. Height relative to track text size.
- spectrumOverlapFactor: number 0..1, default 0.2. Overlap on top of text.
- spectrumBarGap: number, default 1.0. Gap between bars (logical px before per‑screen scale).
- spectrumVerticalRaise: number, default 0.75. Vertical offset relative to text.

Music Players
- pinnedPlayers: string array, default []. Pinned players (priority).
- ignoredPlayers: string array, default []. Players to ignore.
- lastActivePlayers: string array, persisted. Internal list of last active players (managed by app).
- playerSelectionPriority: string array, default ["mpdPlaying","anyPlaying","mpdRecent","recent","manual","first"]. Selection algorithm priority.
- playerSelectionPreset: string, default "default". Preset name for priority ordering.

Media side panel popup
- musicPopupWidth: integer, default 840. Width (logical px; scaled per monitor).
- musicPopupHeight: integer, default 250. Height (logical px; used when content doesn’t define height).
- musicPopupPadding: integer, default 12. Inner padding (logical px).
- musicPopupEdgeMargin: integer, default 4. Horizontal margin between popup and screen edge (logical px; scaled per monitor).

Contrast & Accessibility
- contrastThreshold: number, default 0.5. Threshold for light/dark text selection against backgrounds.
- contrastWarnRatio: number, default 4.5. Target contrast ratio for warnings.

Network
- networkPingIntervalMs: integer, default 30000. Network/ping refresh interval.
- networkNoInternetColor: color string, default "#FF6E00". No‑internet status color.
- networkNoLinkColor: color string, default "#D81B60". No‑link status color.

Weather
- showWeatherInBar: boolean, default false. Weather button in bar.
- useFahrenheit: boolean, default false. Show °F.
- weatherCity: string. City for current weather and forecast.

Visualizer profiles notes
- visualizerProfiles is a dictionary of user profiles. Supported fields per profile:
  - cavaBars, cavaFramerate, cavaMonstercat, cavaGravity, cavaNoiseReduction
  - spectrumFillOpacity, spectrumHeightFactor, spectrumOverlapFactor
  - spectrumBarGap, spectrumVerticalRaise, spectrumMirror
  Any field not defined in a profile falls back to the global value.

Theme/.theme.json (short)
- All typography, colors, paddings, radii, animations, etc. are hierarchical tokens.
- Full list of tokens, types/defaults, and guidance: `Docs/ThemeTokens.md`.
- Up‑to‑date example schema: `Docs/ThemeHierarchical.json`.
- Important groups: `colors.*`, `panel.*`, `shape.*`, `tooltip.*`, `ui.*`, `ws.*`, `timers.*`, `network.*`, `media.*`, `spectrum.*`, `calendar.*`, `weather.*`, `vpn.*`, `time.*`, `volume.*`, `sidePanel.*`.
- Strict mode (`Settings.settings.strictThemeTokens = true`) logs warnings for missing tokens and deprecated flat keys. Flat keys are removed after 2025‑11‑01.

Tools
- Build theme: `node Tools/build-theme.mjs` (merges `Theme/*.jsonc` into `Theme/.theme.json`; add `--check` for CI/hooks).
- Validate theme: `node Tools/validate-theme.mjs [--theme Theme/.theme.json] [--schema Docs/ThemeHierarchical.json] [--strict]` (auto-loads from the `Theme/` parts when present).
- Generate theme schema: `node Tools/generate-theme-schema.mjs` (updates `Docs/ThemeHierarchical.json` from the merged theme parts).
- Validate settings: `node Tools/validate-settings.mjs [--settings ~/.config/quickshell/Settings.json] [--schema Docs/SettingsSchema.json]`.

Settings.json schema and samples
- JSON Schema: `Docs/SettingsSchema.json` (Draft‑07) — types, defaults, and allowed values.
- Preset examples:
  - `Docs/SettingsMinimal.json` — minimal typical overrides.
  - `Docs/SettingsVisualizerSoft.json` — a soft visualizer profile and activation.

Tips
- Color values: `#RRGGBB` or `#AARRGGBB`.
- Integers are logical px before per-screen scaling; runtime scales via `Theme.scale(Screen)` and per-monitor overrides.
- Unsure about a token? Search for it in `Settings/Theme.qml` and `Docs/ThemeTokens.md`.

Keyboard layout indicator (Hyprland)
- The Bar’s keyboard layout indicator updates instantly from Hyprland’s keyboard-layout events for a zero‑lag UI.
- To avoid noise from pseudo keyboards (power-button, video-bus, virtual keyboards), the module identifies the main:true keyboard at init and prefers its events.
- If an event arrives from a non‑main device, the module issues one quick `hyprctl -j devices` snapshot to confirm/correct the label. This keeps the common path fast while fixing rare stale payloads.
- There are no timers/debounces; snapshots are not performed for every event to avoid latency.
- Click behavior: toggles layout via `hyprctl switchxkblayout current next` (no shell involved).
- Recommended Hyprland binding for speed: `bind = $M4, S, switchxkblayout, current, next` (dispatcher syntax, comma‑separated args).
