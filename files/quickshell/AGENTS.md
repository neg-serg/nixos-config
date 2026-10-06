# AGENTS usage in this config (quickshell)

Scope

- This AGENTS.md applies to everything under this directory (`~/.config/quickshell`).
- Prefer using the docs and helper scripts in this tree when they exist.

Relevant docs and scripts

- Docs/SHADERS.md — wedge clip shader design, build, debug, troubleshooting (RU/EN).
- Docs/PANELS.md — panel background transparency controls (RU/EN).
- scripts/compile_shaders.sh — compile every `shaders/*.frag` and `greeter/shaders/*.frag` to `.qsb`
  using Qt 6 Shader Tools.
- scripts/gen_blue_noise.py — regenerate `greeter/assets/blue_noise.png` (void-and-cluster mask used
  by the login screen's dithering); the PNG is committed, run it only when the size changes.
- README.md — quick links and a wedge shader checklist.

Greeter tree is a fork, not a copy (`greeter/`)

- Two entry points, one tree. The login screen of the normal boot is `greeter/login.qml`, a
  session-lock layer inside the session compositor: `hyprland.lua` runs `qs-login-layer` while the
  marker in `$QS_LOGIN_STATE_DIR/state` reads `login` (see `modules/user/session/greetd.nix` and
  `files/quickshell/greeter/lock/LockContent.qml`). `greeter/greeter.qml` is the fork's own shell for
  the old separate greeter session — greetd used to launch it as the `greeter` user
  (`files/gui/hypr/greetd.lua`, kept as the revert path), and it renders the same lock content
  through a `GreeterContext`.
- Neither imports the main tree: the only `qs.*` imports in `greeter/` are its own submodules
  (`qs.lock`, `qs.bar.*`, `qs.notifications`, …).
  `greeter/ShellGlobals.qml` states the reason: the greeter must come up with no user config at all,
  so it cannot depend on `qs.Settings` or `Theme`.
- Eight file names exist in both trees (Bar.qml, ClockWidget.qml, DaemonNotification.qml,
  NotificationDisplay.qml, NotificationManager.qml, NotificationOverlay.qml,
  TrackedNotification.qml, shell.qml) and **all eight differ**, e.g. `Bar.qml` is 1095 lines in the
  bar and 93 in the greeter. The same is true of the notification stack the two trees both have: its
  four files differ in size and structure from the bar's. There is no shared code to lift — a search
  for identical bodies across the two trees finds none.
- What that means in practice: a change to notifications/bar rendering in the main tree does **not**
  reach the greeter, and vice versa. When you touch `Notifications/*`, `Bar/Bar.qml` or
  `Components/*` and the change concerns what a user sees, check the greeter's counterpart by name
  before assuming it is fine; when the fix only makes sense for one tree, leave the other alone and
  say so in the commit message.
- Renaming the greeter's files to make the pairs obvious was considered and skipped: the names are
  how the pairs are found, the entry point path is referenced outside the tree (greetd), and a
  rename would not remove the duplication — it would only hide the correspondence.
- The greeter is linted by the same qmllint gate (`scripts/dev/check-qml-lint.sh` covers
  `files/quickshell` in full, greeter included).

Login screen preview

- `qs -p files/quickshell/greeter/preview.qml` renders the real login card
  (`lock/LockContent.qml`) in a floating window — no session lock, no greetd — so the look can be
  checked and screenshotted while the desktop is running. `PREVIEW_WALLPAPER` picks the backdrop
  (default `~/.cache/greeter-wallpaper`, the file the login layer itself shows). It needs
  `XDG_CONFIG_HOME/quickshell/Theme/.theme.json`, i.e. a logged-in session.

Shaders in the greeter tree

- `greeter/shaders/` holds the login screen's own shaders: `glass_card.frag` (frosted card and its
  shadow), `avatar_frame.frag` (the avatar frame), `crt_screen.frag` (the full-screen CRT pass)
  and `posterize_dither.frag` (the four-colour wallpaper). The palette is k-means in Oklab, computed
  in `greeter/background/BackgroundImage.qml`; the dither mask is `greeter/assets/blue_noise.png`.
- They are compiled by the same `scripts/compile_shaders.sh` and committed as `.qsb` next to their
  source, exactly like the main tree's shaders. Every number stays a theme token in
  `Theme/greeter.jsonc` (read through `GreeterTheme`), so the look can be dialled without touching QML.

Shader build rules (Qt 6)

- Always compile fragment shaders to `.qsb` with: `qsb --glsl "100es,120,150"`.
- Use the provided script:
  `nix shell nixpkgs#qt6.qtshadertools -c bash -lc 'scripts/compile_shaders.sh'`.
- In QML, `ShaderEffect.fragmentShader` must point to a `.qsb` file via
  `Qt.resolvedUrl("../shaders/<name>.frag.qsb")`.

Wedge shader runtime toggles (env)

- `QS_ENABLE_WEDGE_CLIP=1` — enable shader path.
- `QS_WEDGE_DEBUG=1` — show on‑screen overlays and magenta debug inside the wedge.
- `QS_WEDGE_SHADER_TEST=1` — force magenta paint from shader to prove visibility.
- `QS_WEDGE_WIDTH_PCT=NN` — wedge width in percent (0..100).
- (Removed) `QS_WEDGE_TINT_TEST` — panels now rely on `QS_WEDGE_DEBUG=1` + `WlrLayer.Overlay` when
  verifying visibility.

Debugging tips (use where applicable)

- Ensure sources hide when clip is active: bind `ShaderEffectSource.hideSource` to the clip
  `Loader.active`.
- During debug, raise clip `Loader.z` (e.g., `z: 50`) and optionally place bars on
  `WlrLayer.Overlay`.
- Enable `Settings.json` → `debugLogs: true` to get detailed logs.
- Wayland screenshots: `grim -g "$(slurp)" shot.png`.

Settings knobs

- Panel background transparency is configurable via `Settings.settings.panelBgAlphaScale` (0..1
  multiplier). See Docs/PANELS.md.

Style / contribution

- Keep changes minimal and focused; follow existing QML/JS style.
- Do not introduce unrelated changes; mention known unrelated issues separately.
- Update Docs when behavior or workflow changes; the docs are considered part of the contract for
  this config.
- `nix build` is allowed without sudo to sanity-check flakes; feel free to run it after changes
  (counts as a test).
- Running any available linters/formatters (treefmt, statix, deadnix, etc.) is welcome when touching
  relevant files; fix their findings before committing.
- All code comments must be written in English.

Commit style

- Use bracketed scope prefix consistent with this repo’s history, for example:
  `[gui/quickshell] Bar: …`, `[gui/quickshell] Settings: …`, `[gui/quickshell] Docs: …`.
- Keep the subject in imperative mood, short and specific; no trailing period.
- Examples:
  - `[gui/quickshell] Feature: add wedge_clip shader and compile script`
  - `[gui/quickshell] Docs: add SHADERS quick checklist and top-level README links`
  - `[gui/quickshell] Fix: hide base fill and tint when wedge shader is active`
