# Panel Background Transparency

This short doc explains how to control the panels’ background transparency via Settings. For the
Russian translation see `PANELS.ru.md`.

______________________________________________________________________

## English (EN)

### What it does

- `Bar/Bar.qml` reads `panelBgAlphaScale` to compute the base panel background alpha. The value
  (0..1) multiplies the theme background alpha; `0.2` ≈ five times more transparent.

### How to set

Edit `~/.config/quickshell/Settings.json` (live‑reloads):

```json
{
  "panelBgAlphaScale": 0.2
}
```

Notes:

- Higher values darken the bar; lower values make it more transparent.
- The color and original alpha come from `Theme.background`; the scale is applied on top of that.

### Interaction with the wedge shader

- The wedge subtracts from the panel fill. With very transparent panels the wedge appears more
  subtle. If you want a stronger look, either increase `QS_WEDGE_WIDTH_PCT` or reduce transparency
  (increase `panelBgAlphaScale`).
- When debugging (`QS_WEDGE_DEBUG=1`), bars may run on `WlrLayer.Overlay`, so the “hole” shows
  whatever is behind the panel window.
- See `Docs/SHADERS.md` for shader flags and troubleshooting.

### Widget capsules (per-module backgrounds)

- Panel rows are now fully transparent; every widget owns its own rounded capsule.
- Colors come from `Settings.settings.widgetBackgrounds`. Each module looks up its name, then
  `default`, and finally falls back to `#000000` (fully opaque).
- `Components/WidgetCapsule` now hardcodes the same `#000000` fallback so every capsule (and pill)
  is solid unless you override the helper or provide per-widget colors.
- Known keys: `clock`, `workspaces`, `network`, `vpn`, `weather`, `media`, `systemTray`, `volume`,
  `microphone`, `mpdFlags`. You can add more as new widgets adopt the helper.
- Example:

```json
{
  "widgetBackgrounds": {
    "default": "#000000",
    "media": "rgba(15, 18, 30, 0.85)",
    "systemTray": "#201f2dcc"
  }
}
```

Tips:

- Stick to CSS-style colors (`rgba()`, `#rrggbbaa`, `hsl()`).
- Keep base alpha in the 0.7–0.85 range for the requested darker main-panel capsules.
- Capsule padding/height are standardized via `Helpers/CapsuleMetrics.js`. For icon+label widgets
  prefer `Components/CenteredCapsuleRow.qml`, which already wraps `WidgetCapsule`, centers content,
  and handles font/icon alignment without custom rows.
- Prefer the shared `Components/WidgetCapsule.qml` wrapper whenever you add/edit a widget: it
  already looks up colors via `Helpers/WidgetBg.js`, applies borders, and mirrors the capsule
  metrics. Override `backgroundKey`, `paddingScale`, or `verticalPaddingScale` only when a module
  truly needs different spacing.
- If the capsule needs click/tap behavior, use `Components/CapsuleButton.qml` (or wrappers like
  `CenteredCapsuleRow`) instead of hand-written `MouseArea`+`HoverHandler`.
- Audio-level widgets (volume/microphone) must go through `Components/AudioLevelCapsule.qml`; it
  embeds `PillIndicator`, handles hover/scroll, and collapses cleanly when hidden.
- Inline reveal capsules (system tray hover box, future inline menus) should use
  `Components/InlineTrayCapsule.qml` so borders/hover/clip settings stay consistent.

### Panel side margins & flush layout

- Both panel windows now read `panelSideMarginPx` from `Settings.json`. If the key is missing,
  `Theme.panel.sideMargin` (18px by default) is used.
- This single number applies to the left and right bars, so the tray can hug the outer edge without
  hidden spacers.
- Example:

```json
{
  "panelSideMarginPx": 12
}
```

### Right-row lineup (reference)

Right bar widgets are capsule-based and spacing-free. Left → right order:

1. `Media` capsule (optional, follows `showMediaInBar` and player activity).
1. `LocalMods.MpdFlags` (only when MPD is the active player and Media capsule is visible).
1. System tray wrapper (rounded capsule around `SystemTray`).
1. `Microphone` capsule (conditional on mic service visibility).
1. `Volume` capsule.

Keep this order intact so separators remain unnecessary and hover hot-zones are predictable.

When the right panel hides (monitor removed, bar toggled, etc.), its seam window and separators
still disappear in lockstep, but the shader-backed background fill now stays so the translucent
plate remains instead of popping away.

### Network cluster behavior

- The “net cluster” on the left bar now uses a single `LocalMods.NetClusterCapsule`: VPN + link
  icons share the leading slot while throughput text lives in the label lane.
- `NetClusterCapsule` now always uses the Material `lan` glyph for the link status unless you
  explicitly override `linkIconDefault`. The status fallback icons
  (`iconConnected`/`iconNoInternet`/`iconDisconnected`) still apply when `useStatusFallbackIcons` is
  enabled, and VPN glyph swaps are doable via `vpnIconDefault`.
- Only the icon changes color on failure: warning (`Settings.networkNoInternetColor`) when there is
  link but no internet; error (`Settings.networkNoLinkColor`) when the physical link drops. In the
  healthy state the link glyph now reuses the accent color so Ethernet activity pops more, while
  throughput text remains neutral. Use `Helpers/ConnectivityUi.js` to keep formatting/colors
  consistent across VPN/link/speed modules.
- Spacing between the VPN and ethernet icons uses a dedicated `network.capsule.gapTightenPx` token:
  we subtract that many pixels from the leading slot spacing and halve it for side margins, so
  raising the value squeezes both glyphs symmetrically. Adjust
  `network.capsule.iconHorizontalMargin` (overridden to `0` in Theme) if you want the red pill
  bounds to hug the glyph even tighter.
- Icon scale/baseline adjustments come from `Theme.network.icon.scale` / `.vAdjust`. Capsule
  padding/spacing still follow the same Theme tokens, so alignment stays identical even when VPN
  visibility toggles.

______________________________________________________________________
