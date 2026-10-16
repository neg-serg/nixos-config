# Hyprland Plugins

This note pulls together every moving part of the Hyprland plugin stack so the plugins stay aligned
with the compositor without hopping across multiple files. hy3 is the layout; the other plugins
(glass, exposé, shaders, background windows, cursor, capture) are documented under
[Current plugins](#current-plugins).

## Source of Truth and Pinning

- The compositor comes from nixpkgs (`pkgs.hyprland`, 0.56.2 at the time of writing); the `hyprland`
  and `hy3` flake inputs are gone. `nix flake lock --update-input nixpkgs` therefore moves the
  compositor and the nixpkgs-built plugins together.
- `pkgs.hyprlandPlugins.hy3` is nixpkgs' own build: **0.56.0.1** (upstream tag `hl0.56.0.1`),
  compiled by `mkHyprlandPlugin` against the same Hyprland 0.56.2 commit as the session compositor
  (`efb50993780079460b0cbed1363e2166a2de1d9f`). hy3's `PLUGIN_INIT` compares an API hash and refuses
  to load on a mismatch, so plugin and compositor must come from one nixpkgs rev.
- `modules/user/nix-maid/hyprland/overlay.nix` (consolidated from the former
  `modules/nix/hyprland.nix`, now removed) only *adds* what nixpkgs does not carry and patches
  `hypr-dynamic-cursors`; it deliberately does not override hy3. Everything is gated behind
  `features.gui.enable` so headless hosts skip the `pkgs.hyprland` evaluation.
- `pkgs.xdg-desktop-portal-hyprland` is plain nixpkgs (>= 1.4.1, event-loop hangup fix); the 1.4.0
  pin (rev `08d99f72`, ~160% CPU busy spin) was dropped with the input on 2026-09-29.

## Load Model

- Hyprland's Lua config mode auto-detects `hyprland.lua` and ignores the legacy `hyprland.conf`, and
  a plugin cannot be dlopen'd while that file is still being parsed: `plugin = …` lines do nothing
  and `hl.plugin.load` mid-parse is a no-op. Every plugin is loaded from the `hyprland.start` hook
  by a generated `*-setup` helper (`main.nix`), then configured by pushing its Lua settings file
  through `hyprctl eval`. The helpers are in `PATH` and idempotent, so they can be re-run in a live
  session.
- Loads sit before the login-phase branch of the hook: the compositor parses the config exactly
  once, so a plugin loaded only in the session branch never comes up on a greetd login.
- In Lua config mode `hyprctl dispatch` is only a deprecated shorthand and mangles plugin
  dispatchers ("expected a dispatcher"); the plugin's Lua namespace, evaluated with `hyprctl eval`,
  is the working path. Plugin dispatchers are dispatcher objects, so Lua callbacks run them with
  `hl.dispatch(factory(plugin))` — see the `hy3()` bind helper in `hyprland.lua`.

## Home Configuration Wiring

- Everything Hyprland lives under `modules/user/nix-maid/hyprland/` (one domain): `main.nix`
  assembles `environment.nix` (the `hyprland.conf` text) and `hyprlandLuaText` (the
  `@<plugin>_setup@` placeholder substitution in `hyprland.lua`), `files.nix` (home-file links:
  `hyprland.lua`, the plugin settings files, `hyprlock.conf`, `hypridle.conf`) and `services.nix`
  (systemd user services + the Hyprland-related package set). The generated helpers are added to
  `environment.systemPackages`.
- The start hook in `hyprland.lua` execs every helper; `hyprcapture-setup` and
  `hyprdynamiccursors-setup` additionally run as user units on `hyprland-session.target`, because
  their loads must not race the config parse or the login transition.

## Updating Hyprland + plugins

1. Bump nixpkgs (`nix flake lock --update-input nixpkgs`) — the compositor and the nixpkgs-built
   plugins move together.
1. Third-party plugins pinned in `overlay.nix` (hyprexpo, GloView, HyprWindowShade, hyprwinwrap) and
   `hypr-dynamic-cursors` carry revs or patches pinned to a Hyprland commit; bump them with the
   compositor and re-check the patch headers.
1. Rebuild with `sudo nixos-rebuild switch --flake /etc/nixos#<host>` (or the agent-switch flow).
1. A compositor reload keeps loaded plugins but resets their runtime config; re-run the affected
   `*-setup` helper. hy3 itself needs nothing beyond the load.

## Verification Checklist

- `nix path-info .#nixosConfigurations.<host>.pkgs.hyprlandPlugins.hy3` prints the `hy3-0.56.0.1`
  store path.
- `hyprctl plugin list` shows `Plugin hy3 by outfoxxed` (plus the session's other plugins).
- `hyprctl getoption general:layout` prints `str: hy3`, and
  `hyprctl getoption plugin:hy3:tabs:height` prints `int: 22` once the plugin has registered its
  config keys.
- `Hyprland --version` must match the commit the plugins were built against; both come from the same
  nixpkgs, so this holds automatically unless an overlay pin is bumped alone.
- To try a plugin without endangering the session, use a nested instance — see
  [Testing a plugin without endangering the session](#testing-a-plugin-without-endangering-the-session).

## Current plugins

### hy3 (i3-style manual tiling — the layout)

- **Build**: no overlay entry — `pkgs.hyprlandPlugins.hy3` comes from nixpkgs (0.56.0.1, upstream
  tag `hl0.56.0.1`), compiled against the same 0.56.2 commit as the compositor.
- **Load**: `hy3-setup` (`main.nix`) `hyprctl plugin load`s `lib/libhy3.so`, logs every run to
  `$XDG_RUNTIME_DIR/hy3-setup.log` and polls `hyprctl plugin list` for up to ~5 s (a load issued
  while the compositor is busy with the login transition does not always stick). The helper is
  re-runnable in a live session; the load sits before the login branch of the start hook, so the
  plugin is up for the whole session.
- **Layout selection**: `general:layout = "hy3"` in `files/gui/hypr/hyprland.lua` (parsed on every
  reload as well, so a reload keeps the layout while the plugin stays loaded). Before `hy3-setup`
  has run the name is unknown and Hyprland falls back to dwindle; as soon as the plugin registers
  the algorithm, `CWorkspaceAlgoMatcher::updateWorkspaceLayouts` re-tiles every existing workspace
  onto hy3 — that is what makes the static layout selection race-free. The per-workspace
  `layout = "scrolling"|"master"` rules the workspace table used to carry are gone: a rule's layout
  would shadow hy3.
- **Keys**: focus/move/tab binds go through the plugin's Lua factories — `hy3.move_focus` (M4+hjkl,
  arrows, M4+ALT+n/p/f/b), `hy3.move_window` (M4+CTRL+j/k and the tiling submap's SH+hjkl),
  `hy3.move_to_workspace` (M4+SHIFT+1..9/0), `hy3.make_group("tab")` (M4+CTRL+g) and `hy3.focus_tab`
  (M4+CTRL+h/l, M4+CTRL+SHIFT+1..5). The binds are lazy: hy3 is loaded *after* `hyprland.lua` is
  parsed, so the `hy3()` helper resolves `hl.plugin.hy3` at press time and skips silently when the
  plugin is not there.
- **Dormant tape keys**: the core layoutmsg binds (column width, consume/expel, fit/center, the
  scrolling keys) stay in the file but no-op on hy3 — `L(...)` passes no fallback for a hy3
  workspace. The per-app `scrolling_width` rules and the `scrolling`/`master` config blocks stay for
  the case where a workspace is put back onto a core layout.
- **Verified** (nested 0.56.2, 2026-10-16): `hyprctl plugin load libhy3.so` answers `ok` and
  `plugin list` reports `Plugin hy3 by outfoxxed`; `hl.config({general={layout="hy3"}})` flips
  `getoption general:layout` to `hy3` on the running instance; two spawned kitty windows are tiled
  by the plugin (`make_group("tab", {toggle=true})` adds its ~27 px tab bar: y 21→48, height −27 px)
  and `move_focus`/`move_window`/`focus_tab` all return `ok`; `Hyprland --verify-config` on the
  deployed `hyprland.lua` reports `config ok`; no crash lines in the nested log.

### hyprglass (liquid glass)

- **Build**: `modules/user/nix-maid/hyprland/overlay.nix` — v0.8.1, the release pinned to Hyprland
  0.56.2 upstream (`hyprpm.toml` pin); the 0.55 `postPatch` is gone.
  - The build carries one local patch, `hyprglass-layer-backdrop-live.patch`. v0.8.1 parses the
    layer namespace filters only at load and on a config reload, so the keys this session pushes
    *after* the load (they exist only once the plugin registered them) left the whitelist empty —
    and an empty whitelist means "glass every layer", which put the bar and the media card into the
    glass pass with the plugin's *cached* backdrop instead of Hyprland's live layer blur (frozen
    frost until the surface was re-mapped, with its slide animation forcing the re-sample). The
    patch re-parses the filters when the raw values change and invalidates a layer's cached backdrop
    when a commit lands in its sample region — a wallpaper switch is exactly such a commit — while
    the re-sample itself stays rate limited by `layers.live_resample_fps`. `hyprglass-apply --check`
    now covers the layer keys too: a compositor reload resets them to the same dangerous defaults
    while the nine panel keys stay in sync, so nothing else noticed.
- **Load + configure**: the `hyprland.start` hook in `files/gui/hypr/hyprland.lua` runs the
  generated `hyprglass-setup` helper, which does `hyprctl plugin load` and then pushes
  `files/gui/hypr/hyprglass.lua` through `hyprctl eval`. The helper is in PATH, so the glass can be
  (re)applied in a running session without a relogin.
- **Why keys and not the plugin's Lua API**: a plugin cannot be dlopen'd while `hyprland.lua` is
  still being parsed (`hl.plugin.load` is a silent no-op there), and calling
  `hl.plugin.hyprglass.config({...})` at runtime **aborts the compositor** — SIGABRT with the stack
  in `forwardLuaConfig` ← `handleLuaConfig`, reproducible on 0.56.2 + v0.8.1 in a nested instance.
  The regular `plugin = { hyprglass = … }` keys go through the config manager and are stable, so the
  settings live in that form.
- **Glass off**: window rules `hgrm-term` (kitty/term), `hgrm-mpv`, `hgrm-fullscreen` via the
  `hyprglass_disabled` tag.
- **Presets** (custom, defined by `hyprglass-apply` — see below): `scratch` and `media-dark`.
  - `scratch` is attached by tag to every scratchpad window rule in `files/gui/hypr/hyprland.lua`
    (`hyprglass_preset_scratch`): `blur_strength 16` with the maximum of 5 gaussian passes and
    `adaptive_dim = 0`, against the global pair (10.5/4 in the panel's JSON at the time of writing),
    so the desk behind a scratchpad is frosted much harder — and, per the request that the heavier
    frost must not darken the pad, without the adaptive dim that would otherwise ride along: the
    shader scales the frosted colour by `1 - adaptiveDim * smoothstep(0.25, 0.55, blurredLum)`,
    whose curve is tuned for the luminance range a normal-strength blur compresses into.
  - **Per-window overrides** are edited in the Glass panel (win+shift+g, the section below the
    global sliders) and stored in `Settings.json` (`glassWindowOverrides`) plus
    `~/.config/hypr/hyprglass.json`. `hyprglass-apply` turns each entry into a custom preset
    (`win_<class-slug>`) and the `hyprglass_preset_win_<slug>` window rule for that class; the Lua
    is generated from the JSON, never typed by hand. Two mechanics decide what "live" means here:
    preset *values* are resolved by the plugin every frame, so re-tuning an entry re-tunes open
    windows immediately, while a window's *tags* are computed at map time, so the rule itself
    reaches windows of that class opened after the push. A disabled entry gets an empty preset,
    which makes any leftover tag resolve to the theme/global values instead of its old preset.
    Scriptable equivalent (same functions the panel's buttons call):
    `quickshell ipc call globalIPC setGlassWindowOverride '{"class":"music", "enabled":true,"blurStrength":16,"glassOpacity":0.9,"adaptiveDim":0,"tint":"000000cc"}'`,
    `… removeGlassWindowOverride music`, `… listGlassWindowOverrides`. `tint` is RRGGBBAA (the
    plugin's packing, see the shader's closing `mix`) and `""` means "inherit".
  - `music_strong` is the same for the rmpc scratchpad (`music-scratchpad` rule, tag
    `hyprglass_preset_music_strong`): `blur_strength 64` — 4x the scratch preset, a 768 px radius —
    with the same 5 passes and no adaptive dim. The pane draws nothing over its backdrop (0.45
    opacity, no baked slice any more), so the plugin's frost is the whole picture there, and 16 read
    as too weak. `blur_strength` is a plain scale (`value * 12` px) with no clamp: 64, 128 and 256
    are all accepted by the config manager, so this is the knob to turn.
  - `media-dark` (now removed) was attached to the panel's now-playing card through
    `layers.namespace_presets = "qs-music:media-dark"` in `files/gui/hypr/hyprglass.lua`:
    `dark.brightness = 0.40` — ~2x the dark theme's 0.82 — plus the hardest frost
    (`blur_strength 16`, all 5 gaussian passes) and `adaptive_dim = 0`, so the darkness is the tint
    and nothing else. The first pass was `0.55` (exactly 1.5x) with the adaptive dim still riding on
    top; taking that dim off (it multiplied by up to `1 - 0.4` more on a bright backdrop) made the
    plate read too light, hence the lower tint and the extra blur now. The whole namespace was taken
    out of the plugin's layer pass afterwards: that pass frosts the wallpaper it re-samples instead
    of the real backdrop (the reason the bar's surfaces were removed from it), i.e. exactly the
    pseudo-backdrop the card must not show. `qs-music` now uses Hyprland's own layer blur
    (`blur-qs-.*`, `ignore_alpha 0.05` — live framebuffer) over the card's translucent fill, and its
    frame is the thin 1 px hairline the card draws itself. The preset also zeroes the plugin's own
    rim (`fresnel_strength`, `specular_strength`, `edge_thickness`, `refraction_strength`): around a
    small plate that refractive band reads as a thick glowing border, and the frame wanted there is
    the thin 1 px hairline the card draws itself (`Widgets/SidePanel/Music.qml`,
    `border.width: Theme.uiBorderWidth`). Preset values are resolved every frame, so this is a
    push-only knob (no remap of the layer surface). Note the pair separator is `:` (the plugin
    parses these with `parseKeyValuePairs(..., ':')`, `src/main.cpp`), unlike the mask thresholds
    which use `=`.
  - Both are pushed by `hyprglass-apply` with `hyprctl eval` + the plugin's
    `hl.plugin.hyprglass.preset(...)`, because custom presets cannot be expressed as config values
    and the `preset` keyword is unavailable in Lua-config mode —
    `hyprctl keyword plugin:hyprglass:preset …` answers "keyword can't work with non-legacy parsers.
    Use eval." (measured in a nested 0.56.2). `preset()` itself is safe: it goes through
    `handleLuaPreset`, while it is `config()` that aborts the compositor. A `hyprctl reload` drops
    the presets along with the nine knobs, and the next push restores both.
- **Layer glass**: popups and notifications only (`quickshell`, `notifications`, `qs-music`,
  `qs-calendar`, `qs-monitor`, `qs-weather`, `sideleft-weather`, `sysmon-popup`). The always-on bar
  surfaces (`qs-panel`, `quickshell-bar-reserve`, `qs-content-left/right`) are deliberately left to
  Hyprland's own layer blur: hyprglass's layer pass re-samples the background between frames, so the
  glass there flickered between none / normal / double strength (bar strip chroma 1.4 / 9.9 / 18.7,
  std 4.4; 0.06 with the layer glass off), measured on 0.56.2 + v0.8.1 on 2026-09-17. The plugin
  keeps the layer surfaces it has already registered, so a changed namespace list only applies once
  those surfaces are recreated (a quickshell restart).

### hyprexpo (exposé / workspace overview)

- **Build**: `modules/user/nix-maid/hyprland/overlay.nix` — upstream retired hyprexpo from
  `hyprwm/hyprland-plugins` (which is why nixpkgs has no `hyprlandPlugins.hyprexpo`), so the
  maintained fork `sandwichfarm/hyprexpo` is built with nixpkgs' `mkHyprlandPlugin` helper. The rev
  is the fork's own 0.56.2 pin from its `hyprpm.toml` (`5891014c…`), i.e. the plugin and the
  compositor are guaranteed to be the same commit family.
- **Load + configure**: the same load-then-push pattern as hyprglass, in one command: `hypr-expo`
  (`modules/user/nix-maid/hyprland/main.nix`). `hypr-expo push` `hyprctl plugin load`s
  `libhyprexpo.so` and pushes `files/gui/hypr/hyprexpo.lua` through `hyprctl eval`;
  `hypr-expo toggle` loads and configures the plugin *only while it is not registered*, then evals
  the toggle. Both are in PATH.
- **Session start / live reconfiguration**: the `hyprland.start` hook runs `@hyprexpo_setup@`, a
  thin wrapper over `hypr-expo push` (load, then push the keys even when the plugin was already
  there), so an edited `hyprexpo.lua` is applied with `hyprexpo-setup` in a running session. That
  load sits at the very top of the `hyprland.start` handler, *before* its login-phase branch: the
  compositor parses this config once and the branch returns early, so a greetd login used to leave
  hyprexpo unloaded for the whole session (nothing re-parses the config after the password —
  hypr-start restarts units), and the capsule click therefore eval'd a nil namespace.
  HyprWindowShade is hoisted with it; hyprglass deliberately stays in the session branch, where its
  own units load it after the login layer is gone.
- **Why the toggle loads the plugin itself**: `hyprctl eval` of `hl.plugin.hyprexpo.*` answers `ok`
  when the plugin is *not* loaded — the namespace is simply nil — so a session that lost it (the
  start hook never got it in, e.g. the deployed `hyprland.lua` was parsed while its baked-in
  `hyprexpo-setup` store path was already gone) had a workspace capsule whose click did nothing at
  all: the eval printed `ok` and the overview never appeared. The on-demand load is what keeps the
  capsule and `SUPER+grave` working there.
- **Bind**: `SUPER+grave` → `hypr-expo toggle` in `files/gui/hypr/hyprland.lua`. The toggle goes
  through `hyprctl` because the plugin is loaded *after* `hyprland.lua` is parsed, so
  `hl.plugin.hyprexpo` is nil at parse time. In Lua config mode
  `hyprctl dispatch hyprexpo:expo toggle` does **not** work — `dispatch` is a deprecated shorthand
  that rewrites the whole argument list into `hl.dispatch(hyprexpo:expo toggle)` and dies with
  "expected a dispatcher" (reproduced in a nested 0.56.2 instance); the runtime Lua namespace via
  `hyprctl eval` does.
- **Mouse, and why the overview lives in a submap**: the fork does not read mouse buttons on its own
  — it exposes a `select` action that inspects the tile under the pointer and expects a bind on the
  button (upstream README: `bind = , mouse_down, hyprexpo:expo, select`). Binding the *plain* left
  button globally is what broke quickshell here: Hyprland does not pass mouse binds through, so
  every left click stopped reaching the client and nothing in the bar reacted any more (2026-09-20).
  Upstream's answer is the overview submap: on open the plugin enters `hyprexpo` and resets it on
  close, so the binds inside it are live only while the overview is up.
  `files/gui/hypr/hyprland.lua` defines that submap with `hl.define_submap("hyprexpo", ...)` —
  arrows/return for the keyboard focus and confirm, `escape` to cancel, `mouse:272` for the tile
  under the cursor, the token keys for direct selection. Verified on 0.56.2: `hyprctl submap`
  reports `hyprexpo` while the overview is open and `default` after close, a click on a tile
  switches the workspace and closes the overview, and clicks outside the overview reach quickshell
  again. Without the submap a click on a tile does nothing at all — only `escape`, the right button
  and the number keys work (`number_key_mode = workspace` needs no bind). Tiles of *empty*
  workspaces are refused by the plugin itself (`selected workspace is empty`); with `skip_empty = 0`
  they are visible but not selectable. `hypr-expo select` is the same action from the shell, for
  scripts and binds outside the submap; it deliberately does not load the plugin.
- **Look**: `wallpaper_bg = 1` draws the monitor wallpaper behind the tiles. With the plugin's
  default (`0`) the whole overview is the flat `bg_col`, and since the windows here are dark and the
  tiles have `border_color` transparency, opening it read as a black screen with one thumbnail in it
  (measured: 79% of the screen within 1/255 of `bg_col`). The wallpaper, `gaps_out = 24` and a
  visible navy border (instead of `rgba(00000000)`) make the grid legible;
  `show_workspace_numbers = 1` labels each tile.
- **Gesture**: 3-finger swipe with `gesture_direction = "vertical"`; the horizontal 3-finger swipe
  stays with `hl.gesture()` (the scrolling tape), since Hyprland keys gestures per finger count +
  direction and one would shadow the other.
- **Panel entry points**: the workspace capsule in the bar and the IPC both funnel into
  `Services/Expo.qml` (`Quickshell.execDetached` of `hypr-expo toggle`, the same command as the
  bind): `Bar/Modules/WsIndicator.qml` toggles on click, and
  `quickshell ipc call globalIPC toggleOverview` exposes it to scripts and extra binds. The capsule
  sets `activateOnPress: true` (`Components/CapsuleButton.qml`): hovering the left module row
  reveals the pill capsule and slides the workspace capsule sideways, and a release-based tap is
  cancelled when the release lands outside the item — Qt's `TapHandler` insists on
  `parentContains(point)` at release under *every* `gesturePolicy` (qquicktaphandler.cpp,
  setPressed()), so the click was silently lost.

### HyprWindowShade (per-window / per-layer fragment shaders)

- **Build**: `modules/user/nix-maid/hyprland/overlay.nix` — nixpkgs has no
  `hyprlandPlugins.hyprwindowshade`, so it is built with nixpkgs' `mkHyprlandPlugin` helper. The rev
  is the commit its `hyprpm.toml` pins for the Hyprland commit we run (`efb5099378…` = 0.56.2), so
  plugin and compositor stay in one commit family. Upstream ships a Makefile that links GLES/EGL/GL,
  hence `dontUseCmakeConfigure` + `libglvnd` + the dev output of `hyprland` on `PKG_CONFIG_PATH`.
- **Load + configure**: same load-then-push pattern as hyprglass/hyprexpo — the `hyprland.start`
  hook runs `hyprwindowshade-setup`, which `hyprctl plugin load`s `libHyprWindowShade.so` and pushes
  `files/gui/hypr/hyprwindowshade.lua` through `hyprctl eval`. The helper is in PATH, so the rules
  can be re-applied in a live session.
- **Shaders**: `files/gui/hypr/shaders/*.glsl`, linked into `~/.config/hypr/shaders`. GLSL ES 3.20
  with HyprShade's interface (`v_texcoord` / `tex` / `fragColor`) plus the plugin's per-frame
  uniforms (`is_active`, `surface_size`, `time`, `window_box`, …). Editing a shader takes effect on
  the next frame — no reload, no config change.
- **Command**: `shade` (`packages/local-bin/bin/shade`, i.e. `~/.local/bin/shade`) drives the plugin
  from the shell — `shade list`, `shade on [NAME]` (focused window; without NAME an fzf picker over
  the shader directory), `shade off`, `shade class CLASS [NAME]`, `shade layer NS [NAME]`,
  `shade reload`. It calls the plugin through `hyprctl eval` and swallows the spurious "expected a
  dispatcher" failure the plugin cannot avoid. No keybinds are bound on purpose: the effects are
  per-window and transitory, and the bar of SUPER+SHIFT is already full.
- **Shaders shipped**: `crt` (curved glass, scanlines, phosphor triads, chroma misalignment,
  vignette), `vhs` (tracking bands, chroma bleed, tape noise, rolling head-switching bar), `amber`
  (monochrome amber-phosphor monitor with glow), `noir` (hard B/W with animated film grain), plus
  `pixelate` and `dim_unfocused`. `hyprwindowshade.lua` attaches `pixelate` to the Telegram window
  while it is unfocused; `dim_unfocused` is *not* attached anywhere by default — it used to dim the
  terminals whenever they lost focus, and losing focus happens every time a scratchpad is pulled up,
  so the request was to drop that. It stays available per window via `shade on dim_unfocused`.
- **Verified** in a nested 0.56.2 instance: `classshader` on a window drops its unique colour count
  292 → 1; the rule from `hyprwindowshade.lua` leaves an unfocused window at 0.1445 mean luminance /
  0.237 saturation against 0.2356 / 0.496 focused — exactly the shader's 0.62 and 0.55 constants;
  `togglewindowshader` → `clear` measured the same way (unique colours 1649 → 778 → 1649).
  Keypresses themselves cannot be synthesised on this host: `wtype` delivers text to clients, but
  its virtual-keyboard modifier events do not match Hyprland binds (checked against a plain
  `exec_cmd` bind in a nested instance), so the binds are covered by registration
  (`hyprctl binds -j`) is not applicable any more: the binds were dropped in favour of the `shade`
  command, whose actions were measured the same way (`shade on crt` on a window changes its unique
  colour count and mean luminance, `shade off` restores them).

### hyprwinwrap (any window as wallpaper)

- **Build**: `modules/user/nix-maid/hyprland/overlay.nix` — nixpkgs has no
  `hyprlandPlugins.hyprwinwrap`, so it is built with nixpkgs' `mkHyprlandPlugin` helper. The rev is
  the commit upstream's `hyprpm.toml` pins for Hyprland 0.56.2 (`3b6e337b9e…`, 2026-09-10), so
  plugin and compositor stay in one commit family. hyprpm builds it with CMake and
  `install(TARGETS)` drops `libhyprwinwrap.so` into `$out/lib`, so no custom install phase is
  needed; Lua headers come from `lua5_5` (the interpreter Hyprland links — its `lua55.pc` is what
  the plugin's `pkg_search_module(lua55 …)` matches).
- **Load + configure**: same load-then-push pattern as hyprglass/hyprexpo — the `hyprland.start`
  hook runs `hyprwinwrap-setup`, which `hyprctl plugin load`s `libhyprwinwrap.so` and pushes
  `files/gui/hypr/hyprwinwrap.lua` through `hyprctl eval`. The helper is in PATH, so edited
  declarations can be re-applied in a live session. The load sits at the top of the handler, before
  the login branch: the plugin is passive until a matching window is mapped, and the config is
  parsed only once. The declarations cannot live in `hyprland.lua` itself — the plugin is loaded
  *after* that file is parsed, so `hl.plugin.hyprwinwrap` is nil while it runs.
- **Usage**:
  `hl.plugin.hyprwinwrap.window({ class = …, title = …, layer = …, pos_x = …, pos_y = …, size_x = …, size_y = … })`
  pins a window behind the desktop. `class`/`title` are exact matches (not regexes — find them with
  `hyprctl clients`), `pos_*`/`size_*` are screen percentages and `layer` orders several background
  windows. `hl.plugin.hyprwinwrap.focus("class-or-title")` toggles a background window forward.
  `files/gui/hypr/hyprwinwrap.lua` ships without active declarations — it is the place to add the
  app that should run as wallpaper.
- **Patch** (`hyprwinwrap-lua-window-merge.patch`): upstream's `luaWindow()` only appends the spec
  to `gLuaSpecs` and leaves the merge into `gMergedSpecs` to the `config.reloaded` event — which a
  runtime `hyprctl eval` never fires; a real reload would not save it either, because the
  `config.preReload` handler clears `gLuaSpecs` before the merge runs. The patch calls
  `onConfigReloaded()` right after the append, which is what makes the pushed declarations take
  effect at all. Bump this patch together with the rev.
- **Verified** (nested 0.56.2, patched build): the load + eval sequence adopted a
  `kitty --class window-bg` spawned after the eval — the client jumped from its default float (21,21
  486×486) to 0,0 on the full logical monitor, and `focus("window-bg")` toggled it without the "no
  background window matching" error. On the unpatched build the same sequence left the window
  untouched and `focus` failed: the eval-pushed spec never reached `gMergedSpecs`.

### hypr-dynamic-cursors (cursor stretch)

- **Build**: `modules/user/nix-maid/hyprland/overlay.nix` — the plugin comes from nixpkgs
  (`hyprlandPlugins."hypr-dynamic-cursors"`, `0-unstable-2026-07-21`), so the overlay only adds a
  patch instead of re-pinning a rev.
- **Load + configure**: the `hyprdynamiccursors-setup` helper `hyprctl plugin load`s
  `libhypr-dynamic-cursors.so` and pushes `files/gui/hypr/hyprdynamiccursors.lua` through
  `hyprctl eval` (the same load-then-push pattern as hyprglass/hyprexpo). The file sets
  `plugin.dynamic_cursors.mode = "stretch"` (the Lua spelling the plugin README documents; the raw
  config section is `plugin:dynamic-cursors`). The keys only exist after the plugin registered them,
  so the config cannot live in `hyprland.lua` as static config.
- **Login activation**: on a normal greetd login nothing re-parses `hyprland.lua` after the password
  (`hypr-start` restarts units, it does not reload), so the `hl.exec_cmd` in the session branch —
  and with it the helper — never ran: the plugin stayed unloaded and stretch never applied (observed
  2026-10-15). The `hyprdynamiccursors` user unit now runs the helper with
  `hyprland-session.target`, the way hyprglass is loaded by its units, so the login screen still
  keeps the stock cursor; the `hl.exec_cmd` path remains for a hand-started compositor. The helper
  is idempotent (it skips an already-loaded plugin and re-pushes the settings), logs every run to
  `$XDG_RUNTIME_DIR/hyprdynamiccursors-setup.log` and polls `hyprctl plugin list` for up to ~5 s,
  because a load issued while the compositor is still busy with the login transition does not stick.
- **Reload persistence**: a reload keeps the loaded plugin but re-registers its defaults, so the
  runtime push from the helper is lost and the mode falls back to `tilt` (observed 2026-10-15 after
  `hyprctl reload`). The guarded `hl.config` block at the top of `hyprland.lua` re-applies the
  stretch settings on every parse — it is skipped on the first parse, when the plugin is not loaded
  yet, so the login screen keeps the stock cursor. Keep its values in sync with
  `files/gui/hypr/hyprdynamiccursors.lua`.
- **Patch** (`hypr-dynamic-cursors-hyprland-056-signature.patch`): the pinned rev predates Hyprland
  0.56.2, where `CPointerManager::renderSoftwareCursorsFor` gained a `screencopy` bool before
  `forceRender`. The plugin's hardcoded mangled signature still described the one-bool form, so the
  load-time check aborted with "unexpected function signature" (surfaced by `hyprctl plugin load` as
  `plugin crashed/threw in main: std::exception`); the hook handler and the original-call typedef
  forwarded one bool too few as well. The patch updates the typedef, the handler parameters and the
  signature string to the 0.56.2 arity. Bump the patch together with the rev; the override can go
  once nixpkgs carries a rev pinned to 0.56.2.
- **Shake magnification is off**: shake-to-find (`src/other/Shake.cpp`, the KDE-style detector that
  compares total travel against the bounding-box diagonal over a one-second window) fires on fast
  circling (trail/diagonal above `shake:threshold` while the diagonal exceeds 100 px) and magnifies
  the cursor from `shake:base` (4×) upward — that read as "the cursor gets bigger when I spin it",
  so `shake.enabled = false` in both config copies. The `stretch` mode itself stays.
- **Usage**: `stretch` is one of the simulation modes (`tilt`, `rotate`, `stretch`, `none`). After a
  successful load, `hyprctl getoption plugin:dynamic-cursors:mode` prints `str: stretch` and
  `plugin:dynamic-cursors:shake:enabled` prints `bool: false`.

### HyprCapture (screenshots and screen recording)

- **Build**: `modules/user/nix-maid/hyprland/overlay.nix` — the plugin ships its own Nix recipe
  (`nix/package.nix`) and version-suffixed release tags; `v0.4.2-0.56.2` is the tag cut for exactly
  the Hyprland 0.56.2 this nixpkgs carries, so the recipe is evaluated against this tree's `pkgs`
  from the pinned checkout (its `../cmake` and `./aec-sources.json` references resolve inside the
  store). Upstream's build also compiles the private gain-map HEIC codec (libultrahdr + patched
  libheif), the DTLN TFLite AEC runtime and the pinned models, and embeds `$out/bin/hyprcapture-ui`
  as the helper path (`HYPRCAPTURE_DEFAULT_HELPER_PATH`) — the plugin never resolves its helper
  through `PATH`. `lua5_5` is passed explicitly (the unversioned `lua` alias does not exist with
  `allowAliases = false`).
- **Load + configure**: the generated `hyprcapture-setup` helper `hyprctl plugin load`s
  `lib/libhyprcapture.so` and pushes `files/gui/hypr/hyprcapture.lua` through `hyprctl eval` (the
  same load-then-push pattern as hyprglass/hyprexpo). It is started by the `hyprcapture` user unit
  with `hyprland-session.target`, not from `hyprland.lua`: `PLUGIN_INIT` itself calls
  `HyprlandAPI::reloadConfig()` to register the `plugin.hyprcapture.*` keys, and a load issued while
  that file is still being parsed would re-enter the config parser mid-file. The binds in
  `hyprland.lua` are lazy functions, so they resolve `hl.plugin.hyprcapture` at press time. The
  helper is idempotent, logs to `$XDG_RUNTIME_DIR/hyprcapture-setup.log` and polls
  `hyprctl plugin list` for up to ~5 s — the hyprdynamiccursors pattern, because a load issued while
  the compositor is still busy with the login transition does not stick.
- **Reload persistence**: a reload keeps the loaded plugin but re-registers its defaults, so the
  runtime push is lost; the guarded `hl.config` block at the top of `hyprland.lua` re-applies the
  two directories on every parse (false on the first parse, when the plugin is not loaded yet). Keep
  its values in sync with `files/gui/hypr/hyprcapture.lua`.
- **Verified at install time** (2026-10-16): the package builds against this nixpkgs' Hyprland
  0.56.2, `libhyprcapture.so` exports `pluginInit`/`pluginExit`/`pluginAPIVersion`, the embedded
  helper path points at the package's own `bin/hyprcapture-ui`, and the closure carries the TFLite
  AEC runtime, the DTLN models and the gain-map HEIC codec. A nested-instance smoke test is not
  possible from the agent sandbox (no `/dev/dri` access — aquamarine's `CBackend::create()` fails
  there). The load itself was verified in the live session after the switch to generation 2154:
  `hyprcapture.service` exited 0 (`$XDG_RUNTIME_DIR/hyprcapture-setup.log` logs `ok` twice),
  `hyprctl plugin list` reports HyprCapture 0.4.2, `hyprctl getoption plugin:hyprcapture:save_dir`
  prints the configured path with `set: true`, and one capture wrote an owner-only PNG (3840x2160,
  mode 600) into `~/pic/shots` with the plugin's filename template. Check a new session the same
  way: `hyprctl plugin list`, the option, then a capture.
- **Binds**: `SUPER+SHIFT+R` captures fullscreen and `SUPER+SHIFT+CTRL+R` region — the same keys the
  grim/slurp + `pic-info` pair used, now `hl.plugin.hyprcapture.open("fullscreen")` /
  `open("region")`. `open()` captures without the annotation toolbar; the annotated flow is
  `open_editor(mode)`, and `hl.plugin.hyprcapture.record_toggle()` drives recording.
- **Configured keys**: only the output directories (`save_dir` → `$XDG_PICTURES_DIR/shots`,
  `record_save_dir` → `$XDG_VIDEOS_DIR/recordings`); everything else keeps upstream's defaults (save
  \+ clipboard + result thumbnail on).

## Testing a plugin without endangering the session

Plugins run inside the compositor, so a crashing one takes the whole session with it (that is how
the three 2026-09-17 crashes — `forwardLuaConfig` — happened). Test in a **nested instance**
instead. It needs its own runtime dir, otherwise Hyprland tries to reuse the parent's `wayland-1`
socket name and dies on `unable to lock lockfile`:

```sh
stand=/tmp/hpv-stand; mkdir -p "$stand/rt"; chmod 700 "$stand/rt"
ln -sf "$XDG_RUNTIME_DIR/$(basename "$(ls "$XDG_RUNTIME_DIR"/wayland-* | grep -v lock | head -1)")" \
       "$stand/rt/wayland-parent"
printf 'hl.config({ autogenerated = false })\n' > "$stand/stand.lua"
env -u HYPRLAND_INSTANCE_SIGNATURE XDG_RUNTIME_DIR="$stand/rt" WAYLAND_DISPLAY=wayland-parent \
    Hyprland -c "$stand/stand.lua" &

# in a second shell — the nested instance has its own socket + IPC socket:
export XDG_RUNTIME_DIR="$stand/rt"
export HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "$stand/rt/hypr" | head -1)"
hyprctl plugin load /nix/store/…-hyprglass-0.8.1/lib/hyprglass.so
hyprctl plugin list
```

Spawning windows inside the stand exercises the real render path:
`hyprctl eval 'hl.dispatch(hl.dsp.exec_cmd("kitty --class stand-glass"))'` (the legacy
`hyprctl dispatch exec …` form is only a deprecated shorthand in Lua mode).
