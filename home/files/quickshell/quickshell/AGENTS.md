# AGENTS usage in this config (quickshell)

Scope
- This AGENTS.md applies to everything under this directory (`~/.config/quickshell`).
- Prefer using the docs and helper scripts in this tree when they exist.

Relevant docs and scripts
- Docs/SHADERS.md — wedge clip shader design, build, debug, troubleshooting (RU/EN).
- Docs/PANELS.md — panel background transparency controls (RU/EN).
- scripts/compile_shaders.sh — compile all `shaders/*.frag` to `.qsb` using Qt 6 Shader Tools.
- README.md — quick links and a wedge shader checklist.

Shader build rules (Qt 6)
- Always compile fragment shaders to `.qsb` with: `qsb --glsl "100es,120,150"`.
- Use the provided script: `nix shell nixpkgs#qt6.qtshadertools -c bash -lc 'scripts/compile_shaders.sh'`.
- In QML, `ShaderEffect.fragmentShader` must point to a `.qsb` file via `Qt.resolvedUrl("../shaders/<name>.frag.qsb")`.

Wedge shader runtime toggles (env)
- `QS_ENABLE_WEDGE_CLIP=1` — enable shader path.
- `QS_WEDGE_DEBUG=1` — show on‑screen overlays and magenta debug inside the wedge.
- `QS_WEDGE_SHADER_TEST=1` — force magenta paint from shader to prove visibility.
- `QS_WEDGE_WIDTH_PCT=NN` — wedge width in percent (0..100).
- (Removed) `QS_WEDGE_TINT_TEST` — panels now rely on `QS_WEDGE_DEBUG=1` + `WlrLayer.Overlay` when verifying visibility.

Debugging tips (use where applicable)
- Ensure sources hide when clip is active: bind `ShaderEffectSource.hideSource` to the clip `Loader.active`.
- During debug, raise clip `Loader.z` (e.g., `z: 50`) and optionally place bars on `WlrLayer.Overlay`.
- Enable `Settings.json` → `debugLogs: true` to get detailed logs.
- Wayland screenshots: `grim -g "$(slurp)" shot.png`.

Settings knobs
- Panel background transparency is configurable via `Settings.settings.panelBgAlphaScale` (0..1 multiplier). See Docs/PANELS.md.

Style / contribution
- Keep changes minimal and focused; follow existing QML/JS style.
- Do not introduce unrelated changes; mention known unrelated issues separately.
- Update Docs when behavior or workflow changes; the docs are considered part of the contract for this config.

Commit style
- Use bracketed scope prefix consistent with this repo’s history, for example: `[gui/quickshell] Bar: …`, `[gui/quickshell] Settings: …`, `[gui/quickshell] Docs: …`.
- Keep the subject in imperative mood, short and specific; no trailing period.
- Examples:
  - `[gui/quickshell] Feature: add wedge_clip shader and compile script`
  - `[gui/quickshell] Docs: add SHADERS quick checklist and top-level README links`
  - `[gui/quickshell] Fix: hide base fill and tint when wedge shader is active`
