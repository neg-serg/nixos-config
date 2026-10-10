# Per-workspace wallpapers (wl-workspaces)

> Status: **implemented** — `packages/local-bin/bin/wl-workspaces.py` (deployed as
> `~/.local/bin/wl-workspaces`), the user service `wl-workspaces.service`,
> config `files/wl/workspaces.toml` (live link at `~/.config/wl/workspaces.toml`).
> The wallpaper keybind (`Super+Shift+C` and the `Super+Shift+Y` submap) runs
> `wl-workspaces shuffle`.

## Problem

`wl` paints one image per *output*; Hyprland has no per-workspace background of
its own (neither have hyprpaper or swww). The desktop therefore shows the same
image everywhere, although the workspaces here are named by context
(`𐌲:dev`, `𐌸:games`, `𐌳:doc`, `𐍈:photo`, …) and a per-workspace image is a
useful "where am I" signal — visible on empty workspaces and through the
transparent surfaces (kitty, the glass panels).

## How it works

```
Hyprland socket2 (workspace>>, focusedmon>>, monitoradded/removed, activespecial)
  └─ wl-workspaces watch
       ├─ hyprctl -j monitors      → the active workspace of every output
       ├─ Assigner (seed, config)  → workspace → image (persisted)
       └─ wl img <image> --outputs <mon> --transition-type fade … --no-notify
```

- The assignment is a pure function of `(seed, workspace)` and is persisted in
  `~/.local/state/wl/workspaces.json`, so the watcher, `shuffle` and a manual
  `wl-workspaces apply` agree with each other, and a workspace keeps its image
  across a service restart. The seed defaults to the current date (a new day, a
  new set) and `shuffle` re-rolls it.
- Pins live in `~/.config/wl/workspaces.toml`, matched by workspace-name suffix
  (`𐌲:dev` → `dev`), then by id, then `*`. A pin is a file, a directory
  (deterministic pick from it) or `keep`; special workspaces are always kept.
- A workspace whose remembered image disappeared falls back to the pool instead
  of painting nothing (the 2026-09-19 black-desktop scar, see
  `modules/user/nix-maid/sys/wallpaper-sync.nix`); an unknown `transition` name
  is logged and retried without the flag (wl has no `fade` — its list is wipe,
  wave, outer, pixelate, burn, glitch, dreamy, morph, cross-zoom, ink-bleed,
  fluid-*, lava-lamp, chromatic-aberration, lens-distortion, crt-shutdown,
  perlin-wipe, radial-blur, random, none).

## Why the greeter and the palette stay put

Per-workspace swaps must not look like "the user changed the wallpaper":

- swaps are painted with `--no-notify`, so `~/.cache/quickshell-wallpaper-path`
  keeps naming the wallpaper the user picked;
- before every swap the helper writes `~/.local/state/wl/workspaces-swap`
  (`<epoch> <path>`), and `wl-state-sync` skips state changes that match a fresh
  marker — otherwise the `wl-greeter-sync` path unit would copy a new image into
  the greeter cache on every workspace switch;
- matugen is not run automatically anywhere (only as an action in the vicinae
  wallpaper switcher), so the palette keeps following whatever the user chose;
- `wl-state-sync` asks the helper (`wl-workspaces should-skip <path>`) whether a
  state change was one of its own swaps — the marker stays an implementation
  detail of the helper and its rule is covered by the selftest.

## Commands

```sh
wl-workspaces show      # output, workspace, image — no painting
wl-workspaces apply     # paint the current workspaces once (--workspace/--output/--force)
wl-workspaces shuffle   # new seed, repaint now, tell the watcher
wl-workspaces selftest  # mapping/apply/skip logic against fakes (no session)
systemctl --user status wl-workspaces.service
```

## Troubleshooting

- **Nothing changes on workspace switch** — `systemctl --user status
  wl-workspaces` (the watcher logs to the journal): it needs `wl-daemon.service`
  up and `HYPRLAND_INSTANCE_SIGNATURE` in the user manager's environment; the
  event socket is `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock`.
- **One workspace should never repaint** — pin it: `games = "keep"`.
- **Turn the feature off** — `[workspaces] "*" = "keep"` in the config (or stop
  the unit); the wallpaper then stays whatever it was.
- **Images feel slow** — the pool has files up to 12000x6344; wl decodes during
  the transition, so the old image stays a moment. Prefer monitor-sized images
  per workspace or a shorter `duration`.

## Verification

- `wl-workspaces selftest` — exercises config parsing, distinct/deterministic
  assignments, name and id pins, directory pins, missing-file fallback,
  cross-process agreement, the paint flags, the rejected-transition fallback,
  the swap marker, `keep`, the greeter guard and `shuffle`.
  `just lint` runs it (quiet; `WL_WORKSPACES_VERBOSE=1` prints every check).
- Live: the real daemon paints per output with
  `wl img <image> --outputs <mon> --transition-type wipe --duration … --no-notify`
  (`wl query` then reports `[transitioning]`); a *headless* output cannot hold a
  wl surface (`wl-daemon` warns `output not found during surface rebuild`), so
  the lab output is not usable for a visual check.
