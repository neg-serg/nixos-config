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
