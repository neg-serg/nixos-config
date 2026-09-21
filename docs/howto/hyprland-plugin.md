# Hyprland Plugin (hy3)

This note pulls together every moving part related to the `hy3` plugin so we can keep it aligned
with the Hyprland compositor without hopping across multiple files.

## Source of Truth and Pinning

- The flake pins Hyprland to v0.55.4 while `hy3` is pinned via the flake inputs (`flake.nix`:12-39).
  The lock file pins the exact commits under that release.
- Supporting inputs (`hyprland-protocols`, `xdg-desktop-portal-hyprland`) follow Hyprland's inputs,
  so once the Hyprland pin is bumped the portal + protocol packages move in lockstep
  (`flake.nix`:22-25).

## nixpkgs Overlay

- `modules/user/nix-maid/hyprland/overlay.nix` (consolidated from the former
  `modules/nix/hyprland.nix`, now removed) adds the `hyprglass` decoration plugin to
  `pkgs.hyprlandPlugins`, gated behind `features.gui.enable` so headless hosts skip the
  `pkgs.hyprland` evaluation.
- The flake-pinned builds are wired in `flake/lib.nix` `hyprlandOverlay`: it routes
  `pkgs.xdg-desktop-portal-hyprland` (pinned input) so the rest of the configuration consumes it
  without touching `inputs.*` directly. `pkgs.hyprlandPlugins.hy3` is nixpkgs' own build — the `hy3`
  flake input tracked Hyprland 0.56+, failed to load here and was removed (audit 2026-09-15).
- Because everything flows through `pkgs`, Home-Manager modules just reference
  `pkgs.hyprlandPlugins.hy3` and stay agnostic of how the plugin was produced.

## Package Delivery to User Sessions

- The workstation session profile keeps the plugin derivation in the system profile (via the system
  profile). This guarantees the `libhy3.so` payload exists in the store even if a user never
  installs extra Wayland packages manually.

## Home Configuration Wiring

- Everything Hyprland lives under `modules/user/nix-maid/hyprland/` (one domain): `main.nix`
  assembles `environment.nix` (the `hyprland.conf` text: `plugin = hy3/hyprglass` lines plus
  `source` of the lua config), `files.nix` (home-file links: `hyprland.conf`, `hyprland.lua`,
  `hyprlock.conf`, `hypridle.conf`), and `services.nix` (systemd user services + the
  Hyprland-related package set; the session packages moved here from the removed
  `modules/user/session/hyprland.nix`).
- `files.nix` also writes the `permission = ..., plugin, allow` stanza into `hyprland.conf`,
  ensuring hy3 can register without triggering the ecosystem permission guard, plus the wlroots
  screencopy hardening permissions for grim/hyprlock.

## Updating Hyprland + hy3

1. Hyprland itself bumps with nixpkgs (`nix flake lock --update-input nixpkgs`); refresh the
   companion pins with `nix flake update hy3 xdg-desktop-portal-hyprland` (the dedicated `hyprland`
   flake input was removed).
1. Rebuild with `sudo nixos-rebuild switch --flake /etc/nixos#<host>`.
1. Optional: add `--update-input hy3 --update-input xdg-desktop-portal-hyprland` to
   `system.autoUpgrade` if you want unattended bumps; otherwise keep the updates manual to review
   ABI churn.

Because the overlay flows through `pkgs`, no Home-Manager changes are needed when updating; the new
plugin propagates automatically once the system rebuild succeeds.

## Verification Checklist

- Quick health checks after any update:
  - `nix path-info .#legacyPackages.<system>.hyprlandPlugins.hy3` should print the store path that
    backs the plugin for that host's build (replace `<system>` with `x86_64-linux`, etc.).
  - `grep plugin ~/.config/hypr/hyprland.conf` should show the expected `hy3`/`hyprglass` `.so`
    paths exported by `pkgs.hyprlandPlugins.*` (the old `plugins.conf` was folded into
    `hyprland.conf`).
  - `Hyprland --version` output should match the Hyprland commit recorded in `flake.lock` to confirm
    the plugin and compositor were updated together.

Keeping the above pieces in sync prevents the common ABI mismatch issues that surface when hy3 lags
behind Hyprland.

## Current plugins

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
    `adaptive_dim = 0`, against the global pair (10.5/4 in the panel's JSON at the time of
    writing), so the desk behind a scratchpad is frosted much harder — and, per the request that
    the heavier frost must not darken the pad, without the adaptive dim that would otherwise ride
    along: the shader scales the frosted colour by `1 - adaptiveDim * smoothstep(0.25, 0.55,
    blurredLum)`, whose curve is tuned for the luminance range a normal-strength blur compresses
    into.
  - **Per-window overrides** are edited in the Glass panel (win+shift+g, the section below the global sliders) and
    stored in `Settings.json` (`glassWindowOverrides`) plus `~/.config/hypr/hyprglass.json`.
    `hyprglass-apply` turns each entry into a custom preset (`win_<class-slug>`) and the
    `hyprglass_preset_win_<slug>` window rule for that class; the Lua is generated from the JSON,
    never typed by hand. Two mechanics decide what "live" means here: preset *values* are resolved by
    the plugin every frame, so re-tuning an entry re-tunes open windows immediately, while a window's
    *tags* are computed at map time, so the rule itself reaches windows of that class opened after
    the push. A disabled entry gets an empty preset, which makes any leftover tag resolve to the
    theme/global values instead of its old preset. Scriptable equivalent (same functions the panel's
    buttons call): `quickshell ipc call globalIPC setGlassWindowOverride '{"class":"music",
    "enabled":true,"blurStrength":16,"glassOpacity":0.9,"adaptiveDim":0,"tint":"000000cc"}'`,
    `… removeGlassWindowOverride music`, `… listGlassWindowOverrides`. `tint` is RRGGBBAA (the
    plugin's packing, see the shader's closing `mix`) and `""` means "inherit".
  - `music_strong` is the same for the rmpc scratchpad (`music-scratchpad` rule, tag
    `hyprglass_preset_music_strong`): `blur_strength 64` — 4x the scratch preset, a 768 px radius — with
    the same 5 passes and no adaptive dim. The pane draws nothing over its backdrop (0.45 opacity, no
    baked slice any more), so the plugin's frost is the whole picture there, and 16 read as too weak.
    `blur_strength` is a plain scale (`value * 12` px) with no clamp: 64, 128 and 256 are all accepted
    by the config manager, so this is the knob to turn.
  - `media-dark` (now removed) was attached to the panel's now-playing card through
    `layers.namespace_presets = "qs-music:media-dark"` in `files/gui/hypr/hyprglass.lua`:
    `dark.brightness = 0.40` — ~2x the dark theme's 0.82 — plus the hardest frost
    (`blur_strength 16`, all 5 gaussian passes) and `adaptive_dim = 0`, so the darkness is the tint
    and nothing else. The first pass was `0.55` (exactly 1.5x) with the adaptive dim still riding
    on top; taking that dim off (it multiplied by up to `1 - 0.4` more on a bright backdrop) made
    the plate read too light, hence the lower tint and the extra blur now.
    The whole namespace was taken out of the plugin's layer pass afterwards: that pass frosts the
    wallpaper it re-samples instead of the real backdrop (the reason the bar's surfaces were removed
    from it), i.e. exactly the pseudo-backdrop the card must not show. `qs-music` now uses
    Hyprland's own layer blur (`blur-qs-.*`, `ignore_alpha 0.05` — live framebuffer) over the card's
    translucent fill, and its frame is the thin 1 px hairline the card draws itself.
    The preset also zeroes the plugin's own rim (`fresnel_strength`, `specular_strength`,
    `edge_thickness`, `refraction_strength`): around a small plate that refractive band reads as a
    thick glowing border, and the frame wanted there is the thin 1 px hairline the card draws
    itself (`Widgets/SidePanel/Music.qml`, `border.width: Theme.uiBorderWidth`). Preset values are
    resolved every frame, so this is a push-only knob (no remap of the layer surface). Note the pair separator
    is `:` (the plugin parses these with `parseKeyValuePairs(..., ':')`, `src/main.cpp`), unlike the
    mask thresholds which use `=`.
  - Both are pushed by `hyprglass-apply` with `hyprctl eval` + the plugin's
    `hl.plugin.hyprglass.preset(...)`, because custom presets cannot be expressed as config values
    and the `preset` keyword is unavailable in Lua-config mode —
    `hyprctl keyword plugin:hyprglass:preset …` answers "keyword can't work with non-legacy
    parsers. Use eval." (measured in a nested 0.56.2). `preset()` itself is safe: it goes through
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
  `libhyprexpo.so` and pushes `files/gui/hypr/hyprexpo.lua` through `hyprctl eval`; `hypr-expo toggle`
  loads and configures the plugin *only while it is not registered*, then evals the toggle. Both are
  in PATH.
- **Session start / live reconfiguration**: the `hyprland.start` hook runs `@hyprexpo_setup@`, a thin
  wrapper over `hypr-expo push` (load, then push the keys even when the plugin was already there), so an
  edited `hyprexpo.lua` is applied with `hyprexpo-setup` in a running session.
  That load sits at the very top of the `hyprland.start` handler, *before* its login-phase branch: the
  compositor parses this config once and the branch returns early, so a greetd login used to leave
  hyprexpo unloaded for the whole session (nothing re-parses the config after the password — hypr-start
  restarts units), and the capsule click therefore eval'd a nil namespace. HyprWindowShade is hoisted
  with it; hyprglass deliberately stays in the session branch, where its own units load it after the
  login layer is gone.
- **Why the toggle loads the plugin itself**: `hyprctl eval` of `hl.plugin.hyprexpo.*` answers `ok`
  when the plugin is *not* loaded — the namespace is simply nil — so a session that lost it (the start
  hook never got it in, e.g. the deployed `hyprland.lua` was parsed while its baked-in `hyprexpo-setup`
  store path was already gone) had a workspace capsule whose click did nothing at all: the eval printed
  `ok` and the overview never appeared. The on-demand load is what keeps the capsule and
  `SUPER+grave` working there.
- **Bind**: `SUPER+grave` → `hypr-expo toggle` in `files/gui/hypr/hyprland.lua`. The toggle goes through
  `hyprctl` because the plugin is loaded *after* `hyprland.lua` is parsed, so `hl.plugin.hyprexpo` is nil
  at parse time. In Lua config mode `hyprctl dispatch hyprexpo:expo toggle` does **not** work — `dispatch`
  is a deprecated shorthand that rewrites the whole argument list into `hl.dispatch(hyprexpo:expo toggle)`
  and dies with "expected a dispatcher" (reproduced in a nested 0.56.2 instance); the runtime Lua
  namespace via `hyprctl eval` does.
- **Mouse, and why the overview lives in a submap**: the fork does not read mouse buttons on its own — it
  exposes a `select` action that inspects the tile under the pointer and expects a bind on the button
  (upstream README: `bind = , mouse_down, hyprexpo:expo, select`). Binding the *plain* left button globally
  is what broke quickshell here: Hyprland does not pass mouse binds through, so every left click stopped
  reaching the client and nothing in the bar reacted any more (2026-09-20). Upstream's answer is the
  overview submap: on open the plugin enters `hyprexpo` and resets it on close, so the binds inside it are
  live only while the overview is up. `files/gui/hypr/hyprland.lua` defines that submap with
  `hl.define_submap("hyprexpo", ...)` — arrows/return for the keyboard focus and confirm, `escape` to
  cancel, `mouse:272` for the tile under the cursor, the token keys for direct selection. Verified on
  0.56.2: `hyprctl submap` reports `hyprexpo` while the overview is open and `default` after close, a click
  on a tile switches the workspace and closes the overview, and clicks outside the overview reach quickshell
  again. Without the submap a click on a tile does nothing at all — only `escape`, the right button and the
  number keys work (`number_key_mode = workspace` needs no bind). Tiles of *empty* workspaces are refused by
  the plugin itself (`selected workspace is empty`); with `skip_empty = 0` they are visible but not
  selectable. `hypr-expo select` is the same action from the shell, for scripts and binds outside the
  submap; it deliberately does not load the plugin.
- **Look**: `wallpaper_bg = 1` draws the monitor wallpaper behind the tiles. With the plugin's default
  (`0`) the whole overview is the flat `bg_col`, and since the windows here are dark and the tiles have
  `border_color` transparency, opening it read as a black screen with one thumbnail in it (measured: 79% of
  the screen within 1/255 of `bg_col`). The wallpaper, `gaps_out = 24` and a visible navy border (instead of
  `rgba(00000000)`) make the grid legible; `show_workspace_numbers = 1` labels each tile.
- **Gesture**: 3-finger swipe with `gesture_direction = "vertical"`; the horizontal 3-finger swipe
  stays with `hl.gesture()` (the scrolling tape), since Hyprland keys gestures per finger count +
  direction and one would shadow the other.
- **Panel entry points**: the workspace capsule in the bar and the IPC both funnel into
  `Services/Expo.qml` (`Quickshell.execDetached` of `hypr-expo toggle`, the same command as the bind):
  `Bar/Modules/WsIndicator.qml` toggles on click, and `quickshell ipc call globalIPC
  toggleOverview` exposes it to scripts and extra binds. The capsule sets
  `activateOnPress: true` (`Components/CapsuleButton.qml`): hovering the left module row
  reveals the pill capsule and slides the workspace capsule sideways, and a
  release-based tap is cancelled when the release lands outside the item — Qt's
  `TapHandler` insists on `parentContains(point)` at release under *every*
  `gesturePolicy` (qquicktaphandler.cpp, setPressed()), so the click was silently lost.


### HyprWindowShade (per-window / per-layer fragment shaders)

- **Build**: `modules/user/nix-maid/hyprland/overlay.nix` — nixpkgs has no
  `hyprlandPlugins.hyprwindowshade`, so it is built with nixpkgs' `mkHyprlandPlugin` helper. The
  rev is the commit its `hyprpm.toml` pins for the Hyprland commit we run (`efb5099378…` = 0.56.2),
  so plugin and compositor stay in one commit family. Upstream ships a Makefile that links
  GLES/EGL/GL, hence `dontUseCmakeConfigure` + `libglvnd` + the dev output of `hyprland` on
  `PKG_CONFIG_PATH`.
- **Load + configure**: same load-then-push pattern as hyprglass/hyprexpo — the `hyprland.start`
  hook runs `hyprwindowshade-setup`, which `hyprctl plugin load`s `libHyprWindowShade.so` and pushes
  `files/gui/hypr/hyprwindowshade.lua` through `hyprctl eval`. The helper is in PATH, so the rules
  can be re-applied in a live session.
- **Shaders**: `files/gui/hypr/shaders/*.glsl`, linked into `~/.config/hypr/shaders`. GLSL ES 3.20
  with HyprShade's interface (`v_texcoord` / `tex` / `fragColor`) plus the plugin's per-frame
  uniforms (`is_active`, `surface_size`, `time`, `window_box`, …). Editing a shader takes effect on
  the next frame — no reload, no config change.
- **Command**: `shade` (`packages/local-bin/bin/shade`, i.e. `~/.local/bin/shade`) drives the
  plugin from the shell — `shade list`, `shade on [NAME]` (focused window; without NAME an fzf
  picker over the shader directory), `shade off`, `shade class CLASS [NAME]`, `shade layer NS
  [NAME]`, `shade reload`. It calls the plugin through `hyprctl eval` and swallows the spurious
  "expected a dispatcher" failure the plugin cannot avoid. No keybinds are bound on purpose: the
  effects are per-window and transitory, and the bar of SUPER+SHIFT is already full.
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
