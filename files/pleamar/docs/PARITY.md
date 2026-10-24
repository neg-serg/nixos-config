# Port status: QuickShell → pleamar

What of the legacy shell in `files/quickshell` has a counterpart in this port, and what has not.
Written because "the capsules are glass" was asked for twice and delivered late: a list makes the
gaps visible before they are asked about again.

**How this was made.** The inventory is the QML tree itself (`Bar/Modules`, `Components`,
`Services`, the top-level areas, and the two big trees `Chaldea/` and `greeter/`). A counterpart is
a scene (`shells/*`), a plugin (`lib/plugins/*`) or a library
(`lib/{capsule,icons,menu,palette}.plm`); evidence is the file headers that name their legacy
(`// Legacy: …`), `docs/INTERFACES.md`, and the behaviour itself. Statuses are by behaviour, not by
line: "ported" means the thing works in the port, not that its QML was translated one-to-one.

**Legend**

|             |                                                                                                                                                           |
| ----------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **ported**  | a counterpart exists and its behaviour is there                                                                                                           |
| **partial** | a counterpart exists with a known gap (named in the note)                                                                                                 |
| **absent**  | nothing in the port                                                                                                                                       |
| **engine**  | the QML object is plumbing the scene language replaces outright (a behaviour, a layout host, a texture helper); there is nothing to port object by object |

## Bar (`Bar/`, 24 files)

| QuickShell object                                | port counterpart                                  | status  | note                                                       |
| ------------------------------------------------ | ------------------------------------------------- | ------- | ---------------------------------------------------------- |
| `Bar.qml` (three layer surfaces, reserve, slide) | `shells/bar/bar.plm`                              | ported  | one surface, reserve and slide via `surface`/`body`        |
| `Modules/ClockWidget`                            | bar `Clock`                                       | ported  | size and tone measured; heals its own size on 0.4.29       |
| `Modules/Time`                                   | bar `Clock` (date part)                           | ported  |                                                            |
| `Modules/WsIndicator`                            | bar `WsCapsule`                                   | ported  | SVG icon vs font glyph; the owner keeps the smaller glyph  |
| `Modules/KeyboardLayoutHypr`                     | bar `KeyboardCluster`                             | ported  |                                                            |
| `Modules/NetClusterCapsule`                      | bar `NetCluster`                                  | ported  | digits, tracking, leading-zero dimming, unit in the accent |
| `Modules/NetFlowCapsule`                         | bar + `panels/pages/network.plm`                  | ported  |                                                            |
| `Modules/NetFlowPopup`                           | `panels/pages/network.plm`                        | partial | live flow chart and per-app table not compared             |
| `Modules/SystemMonitorCapsule`                   | bar `SysmonPair`                                  | ported  | glyph sizes measured against the reference                 |
| `Modules/SystemMonitorPopup`                     | `panels/pages/system.plm`                         | partial | history plot absent                                        |
| `Modules/Media`                                  | bar `MediaCapsule`                                | ported  | cover, title, time, cover-derived accent                   |
| `Modules/MediaTransport`                         | bar `MediaCapsule` hover row                      | ported  | prev/play/next + analyser on hover                         |
| `Modules/MpdFlags`                               | `lib/plugins/mpd`                                 | ported  |                                                            |
| `Modules/Volume`                                 | bar `VolCapsule` + `panels/pages/volume.plm`      | ported  |                                                            |
| `Modules/AudioEndpointTile`                      | `panels/pages/volume.plm`                         | partial | endpoint tiles drawn; device switching unverified          |
| `Modules/Microphone`                             | bar `MicCapsule` + volume page                    | ported  |                                                            |
| `Modules/GenelecWidget`                          | `lib/plugins/genelec` + bar `Gen` capsule         | ported  |                                                            |
| `Modules/WeatherButton`                          | bar `WeatherCapsule` + `panels/pages/weather.plm` | partial | values come from the port's own cache; no network here     |
| `Modules/Calendar`                               | `panels/pages/calendar.plm`                       | ported  |                                                            |
| `Modules/PillCapsule`                            | `lib/plugins/pill` + bar pill                     | ported  |                                                            |
| `Modules/SystemTray`                             | bar `TrayIcon` rows                               | partial | icons and hover expand; no menu, no raise                  |
| `Modules/CustomTrayMenu`                         | —                                                 | absent  | `lib/menu.plm` exists but nothing uses it yet              |
| `Modules/BuildStatus`                            | —                                                 | absent  | nix build badge                                            |
| `Modules/BuildStatusPopup`                       | —                                                 | absent  |                                                            |

## Components (`Components/`, 42 files)

| QuickShell object                                                                                                                                                            | port counterpart                     | status  | note                                                                        |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ | ------- | --------------------------------------------------------------------------- |
| `WidgetCapsule`                                                                                                                                                              | `lib/capsule.plm`                    | ported  | fill, rim, edge, shadow, glass                                              |
| `CapsuleButton`                                                                                                                                                              | capsule + `zone`                     | ported  |                                                                             |
| `CenteredCapsuleRow`                                                                                                                                                         | `row` / `column`                     | engine  | the language lays out                                                       |
| `LinearSpectrum`, `IPhoneSpectrum`, `Cava`                                                                                                                                   | `lib/plugins/spectrum`               | ported  |                                                                             |
| `MonitorBar`                                                                                                                                                                 | bar `SysmonPair` bar                 | ported  |                                                                             |
| `MoonPhaseIcon`                                                                                                                                                              | `shells/bar/moon.wgsl`               | ported  | 4×4 Bayer, band 0.45 R, phase geometry                                      |
| `PanelTooltip`, `StyledTooltip`                                                                                                                                              | bar tooltip (`tip_open`, `bar.luau`) | partial | one line, no rich layout                                                    |
| `OverlayFrame`, `TriangleOverlay`                                                                                                                                            | glass edge, bar `line` separator     | partial | the cut's tone is now the reference's formula; the frame is not a component |
| `TrayIcon`, `InlineTrayCapsule`                                                                                                                                              | bar `TrayIcon`                       | partial | no menu host                                                                |
| `ConnectivityCapsule`, `ConnectivityIconSlot`, `ConnectivityState`                                                                                                           | bar `NetCluster` + `bar.luau`        | partial | no VPN detail row                                                           |
| `AudioLevelCapsule`, `AudioEndpointCapsule`                                                                                                                                  | volume page                          | partial |                                                                             |
| `MaterialIcon`, `BaselineAlignedIcon`, `GlyphShadow`                                                                                                                         | `lib/icons.plm`, text `family:`      | partial | no optical baseline tuning                                                  |
| `Spinner`                                                                                                                                                                    | `spin`/`wave` on any property        | engine  |                                                                             |
| `SlideReveal`, `RotateBehavior`, `ColorFastInOutBehavior`                                                                                                                    | springs and `rotate`                 | engine  |                                                                             |
| `NumberFadeBehavior`, `NumberStdInBehavior`, `NumberStdOutBehavior`                                                                                                          | —                                    | absent  | digit roll animations                                                       |
| `ContrastGuard`, `HiDpiImage`, `ProcessRunner`                                                                                                                               | —                                    | engine  | rasteriser and process handling are the renderer's/logic's                  |
| `PanelLayer`, `PanelOverlaySurface`, `PanelWithOverlay`, `OverlayToggle`, `OverlayToggleCapsule`, `SubmenuHost`, `DelegateEntry`, `TrayRaise`, `IconButton`, `PillIndicator` | scenes/`popup`/`zone`                | partial | the mechanisms exist (`popup`, `layer`, zones); not as named components     |

## Services (`Services/`, 19 files)

| QuickShell object                        | port counterpart                              | status  | note                                            |
| ---------------------------------------- | --------------------------------------------- | ------- | ----------------------------------------------- |
| `Audio`                                  | `audio` service                               | ported  |                                                 |
| `Connectivity`                           | `network` service + `bar.luau`                | partial | no VPN state machine                            |
| `CoverResolver`                          | `lib/plugins/cover`                           | ported  |                                                 |
| `Expo`                                   | `shells/overview`                             | ported  |                                                 |
| `Genelec`                                | `lib/plugins/genelec`                         | ported  |                                                 |
| `HyprlandWatcher`, `HyprlandWatcherImpl` | `hyprctl` polling in the scenes               | partial | no event socket; workspaces are polled          |
| `MusicManager`                           | `media` service + `art.plm`                   | ported  | cover accent now sampled (`AccentSampler` port) |
| `MusicMeta`                              | `lib/plugins/meta`                            | ported  |                                                 |
| `MusicPlayers`, `MusicPosition`          | `media` service                               | partial | one player at a time, no `url` field upstream   |
| `OverlayManager`                         | `shells/overlay`                              | ported  |                                                 |
| `PillTracker`                            | `lib/plugins/pill`                            | ported  |                                                 |
| `SystemMonitor`                          | `bar.luau` probe + `panels/pages/system.plm`  | ported  |                                                 |
| `Timers`                                 | `every`, `after`, `blink`, `wave`             | engine  |                                                 |
| `TrayController`                         | `tray` service                                | partial | no menu/raise                                   |
| `WallpaperAccent`                        | `scripts/theme/theme.sh`                      | ported  |                                                 |
| `Weather`                                | `bar.luau` fetch + `panels/pages/weather.plm` | partial | the host cannot reach `api.open-meteo.com`      |
| `WidgetRegistry`                         | settings + `widget.*` facts                   | partial | no runtime registry                             |

## Areas and trees

| QuickShell area                                                                      | port counterpart                          | status          | note                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| ------------------------------------------------------------------------------------ | ----------------------------------------- | --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Bar/` (whole)                                                                       | `shells/bar`                              | ported          |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `Notifications/` (8 files)                                                           | `shells/notifications`                    | partial         | cards drawn; history and DND unverified                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `overview/`                                                                          | `shells/overview`                         | ported          |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `Widgets/SidePanel/` (`Music`, `MusicPopup`, `MusicDetailRow`, `Weather`, `SunIcon`) | `panels/pages/{media,weather}.plm`        | partial         | the now-playing card and the weather drawer exist; detail rows differ                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `Widgets/ScreenshotToast`                                                            | `shells/toast`                            | partial         |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `Widgets/Glass` (the panel only writes `~/.config/hypr/hyprglass.json`)              | `glass:` on the scene's own bodies        | partial         | **the glass is the compositor's**: a Hyprland plugin blurs/refracts the whole surface, tuned by that JSON, and this host currently does not load it (a live load crashed the compositor twice on 2026-09-17). A scene cannot ask it for anything. pleamar's `glass:` is per shape — refraction at the bevel, an edge highlight, frost — which is *more* than the reference shows and not the same pipeline. Neither does global illumination: both sample the backdrop and add highlights |
| `greeter/` (24 files: `greeter.qml`, themes, `lock/`)                                | `shells/lock` (login/lock)                | partial         | the card is ported; the theme variants are not                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `Chaldea/` (295 files, 403 total)                                                    | `panels/pages/media.plm`, `shells/lock`   | absent (as art) | the player and lockscreen *skins*: sleeves, ledgers, glyph art. The functional player is ported; the 295 art files are not, by design                                                                                                                                                                                                                                                                                                                                                     |
| `Theme/` (21 jsonc)                                                                  | `lib/palette.plm`, `theme.plm`, `art.plm` | ported          |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `Helpers/` (31 files)                                                                | `bar.luau`, `*.plm`, `theme.sh`           | partial         | `AccentSampler`, `WeatherIcons`, `WorkspaceName`, `Format` ported; `MenuUtils`, `IdleInhibitor`, `IPCHandlers`, `PillHistory` (→ plugin), `GuardedFileView` not                                                                                                                                                                                                                                                                                                                           |
| `shaders/` (4 wgsl)                                                                  | `shells/bar/moon.wgsl`, `glass:`          | partial         | the glass shaders are the renderer's; the moon is ours                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `Tools/`, `scripts/`, `Docs/`                                                        | —                                         | absent          | build/tooling, not shell behaviour                                                                                                                                                                                                                                                                                                                                                                                                                                                        |

## The short version

Ported, in the sense that the thing works: the bar and all its capsules, the launcher, notifications
(cards), overlay, overview, the drawer pages, the plugins (cover, meta, mpd, pill, spectrum,
genelec), the palette and its scripts, and the login/lock card.

Absent outright: the tray menu and anything built on it (`CustomTrayMenu`, `SubmenuHost`,
`MenuUtils`), the build status badge, the number-roll animations, and Chaldea's 295 art files.

Partial, with the gap named above: tray, connectivity/VPN, weather values (no network on this host),
tooltips, system-monitor history, notifications history, the greeter's theme variants, and the
helper set.
