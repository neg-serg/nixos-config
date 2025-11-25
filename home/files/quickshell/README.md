# Quickshell Config (User Setup)

Quick links
- Docs/SHADERS.md — shader wedge clipping, build/debug, troubleshooting (RU/EN)
- Docs/PANELS.md — panel background transparency settings (RU/EN)
- scripts/compile_shaders.sh — builds `.frag` → `.qsb` (Qt 6 Shader Tools)

Wedge Shader Quick Checklist
- Build: `nix shell nixpkgs#qt6.qtshadertools -c bash -lc 'scripts/compile_shaders.sh'`
- Test visibility: `QS_ENABLE_WEDGE_CLIP=1 QS_WEDGE_DEBUG=1 QS_WEDGE_SHADER_TEST=1 qs`
- If no magenta: ensure `.qsb` files exist, debug puts bars on `WlrLayer.Overlay`; enable `debugLogs` in `Settings.json`
- If wedge not obvious: `QS_WEDGE_WIDTH_PCT=60` to temporarily widen the seam
- Ensure `ShaderEffectSource.hideSource` is bound to clip `Loader.active`; temporarily raise clip `z` (e.g. 50)
- Panel transparency influences wedge appearance — see Docs/PANELS.md

Notes
- Qt 6 `ShaderEffect` requires precompiled `.qsb` files (use `qsb --glsl "100es,120,150"`).
- Run the shader build script from this directory (`~/.config/quickshell`).

Migration Log
- 2025-11: Decorative separators were removed across the bar, menus, and docs. Delete any local overrides such as `mediaTitleSeparator`, `panel.menu.separatorHeight`, `panel.sepOvershoot`, and every `ui.separator.*` token in custom `Settings.json`/`Theme/.theme.json`. Use spacing/padding only; rebuild shaders after updating themes.
- 2025-11: Panel rows are now fully transparent. Every widget is responsible for its own rounded capsule background using `Helpers/WidgetBg.js` and the `Settings.settings.widgetBackgrounds` map (see Docs/PANELS.md). Capsules now default to a solid black fill; override per-widget if you need lighter treatments.
- 2025-11: The left/right window margins are controlled by `panelSideMarginPx` (Settings.json). This value overrides `Theme.panel.sideMargin` so both panels hug the screen edges equally; remove any hand-tuned padding from modules.
- 2025-11: `Components/WidgetCapsule.qml` is the canonical capsule wrapper (background lookup, border, padding, metrics). When touching a widget that draws its own pill, replace ad-hoc `Rectangle` logic with this component and override `backgroundKey`/padding props only when necessary.
- 2025-11: `Components/CenteredCapsuleRow.qml` combines `WidgetCapsule` with a baseline-aligned icon+label row; use it instead of hand-built `Row`/`FontMetrics` stacks for SmallInlineStat-style modules (network, VPN, keyboard indicator, etc.).
- 2025-11: `Components/CapsuleButton.qml` wraps `WidgetCapsule` with built-in pointer handlers; prefer it (directly or via `CenteredCapsuleRow`) for clickable capsules such as the clock, weather, or layout indicator widgets.
- 2025-11: `Components/AudioLevelCapsule.qml` is the shared volume/microphone wrapper. It already embeds `PillIndicator`, handles hover/scroll, and collapse-on-hide logic — do not recreate this pattern in modules.
- 2025-11: `Components/InlineTrayCapsule.qml` holds the inline SystemTray background/border defaults. Reuse it for any other inline reveal capsules instead of repeating the configuration block.
- 2025-11: `Helpers/ConnectivityUi.js` centralizes the network color palette and the formatters (`formatThroughput`, `iconColor`), so VPN/link/usage modules stay in sync.
- 2025-11: Connectivity UI changes — VPN + link glyphs + throughput now live inside a single `LocalMods.NetClusterCapsule` on the left bar. The link glyph still picks a random icon from the `graph-*` / `schema` / `family_*` pool, and only the icon shifts color (orange for “no internet”, pink for “no link”); throughput text stays neutral.

Systemd user service (single instance)
1. Copy the unit file: `mkdir -p ~/.config/systemd/user && cp Tools/systemd/quickshell-panel.service ~/.config/systemd/user/`.
2. Reload units: `systemctl --user daemon-reload`.
3. Enable + start: `systemctl --user enable --now quickshell-panel.service`.
4. Afterwards control the panel with `systemctl --user restart quickshell-panel.service` instead of launching `qs` manually — systemd keeps only one instance alive and auto-restarts on crashes.
