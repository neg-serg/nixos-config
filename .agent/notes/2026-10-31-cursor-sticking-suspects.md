# Cursor sticking: suspects and measurements (2026-10-31)

The user reports the pointer occasionally "sticking". Nothing was changed in this session — this is
the evidence collected so far plus the list of components that can own or synthesize pointer state,
so the next session can go straight at the suspect instead of re-deriving the map.

Related: `.agent/notes/2026-10-23-pleamar-cursor-eaten.md` (pleamar hiding the cursor over its own
layer surfaces — the other cursor symptom, already patched), `docs/CURSORS.md` (theme, stretch
plugin, hyprcursor assets).

## Is pleamar's resource use the cause? No.

Measured live, per systemd user unit (`MemoryCurrent`/`MemoryPeak`, CPU from `CPUUsageNSec` deltas
over 60 s, machine under a from-source system build, load ~18):

| scene         | RSS now | peak    | CPU (% of one core)               |
| ------------- | ------- | ------- | --------------------------------- |
| bar           | 69 MB   | 126 MB  | 7.8                               |
| panels        | 39 MB   | 176 MB  | 1.5                               |
| notifications | 28 MB   | 47 MB   | 12.6                              |
| launcher      | 19 MB   | 28 MB   | 1.4                               |
| toast         | 18 MB   | 24 MB   | 1.2                               |
| **total**     | ~172 MB | ~400 MB | **24.5 % (0.76 % of 32 threads)** |

Per unit caps: `MemoryHigh = 256M`, `MemoryMax = 512M`, `CPUQuota = 100%`
(`modules/user/nix-maid/gui/pleamar.nix:259-261`).

`notifications` burning 12.6 % of a core while its journal shows no notifications at all is a
separate finding worth its own look (its parity budget in `files/pleamar/docs/PARITY.md` is 0.5 % of
a core, recorded residue 1.0 %).

## What can own the pointer right now

| component                                       | relationship to the pointer                                                                                                                                     | state at measurement                                                                 |
| ----------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| pleamar bar/panels/notifications/toast/launcher | set a cursor **shape** on their layer surfaces (`packages/overlays/pleamar-cursor-shape.patch` re-says the shape inside and repairs a wipe in ~0.5 s)           | 5 scenes running                                                                     |
| pleamar-overlay                                 | full-screen input catcher (drawers, dismissal)                                                                                                                  | **inactive**                                                                         |
| **neru**                                        | creates an **evdev pointer proxy** — log: `Evdev pointer proxy created for a keyboard that reports pointer capability` — and drives the pointer for hints/grids | running                                                                              |
| ydotoold                                        | virtual pointer via uinput                                                                                                                                      | running                                                                              |
| kanata                                          | key remapping; explicitly excludes the ydotoold device (`device [/dev/input/event28:ydotoold virtual device] is excluded`)                                      | running                                                                              |
| dynamic-cursors (Hyprland plugin)               | stretches the cursor shape by movement                                                                                                                          | loaded, `plugin:dynamic_cursors:enabled = false` (verified with `hyprctl getoption`) |
| hyprexpo / GloView / hymission                  | overview overlays that take the pointer while open (`show_cursor = 1` in `files/gui/hypr/hyprexpo.lua:125`)                                                     | loaded                                                                               |
| hy3                                             | tiling with mouse-resize bindings                                                                                                                               | loaded                                                                               |
| HyprCapture                                     | screenshots with a crosshair cursor                                                                                                                             | loaded                                                                               |
| hyprlock                                        | `hide_cursor = true` (`files/gui/hypr/hyprlock.conf:17`)                                                                                                        | —                                                                                    |
| theme                                           | Alkano-aio, size 23, hyprcursor + XCURSOR/HYPRCURSOR aligned                                                                                                    | —                                                                                    |

Full plugin list (`hyprctl plugin list`): HyprWindowShade, GloView, hyprwinwrap, hyprexpo, hy3,
hymission, HyprCapture, dynamic-cursors.

## Checked, did not reproduce

- **Cursor-shape churn.** The Hyprland log holds 5862
  `Cursor buffer imported into KMS with id 499/509` lines, alternating between two buffers — but **0
  in a 10 s window right now**, so it is session-start and wallpaper-change traffic, not a live
  fight over the shape.
- dynamic-cursors is not fighting anyone: disabled by config, as `files/gui/hypr/hyprland.lua:45-47`
  intends.
- pleamar-overlay is not mapped, so no invisible surface is eating input.

## Suspect ranking (unconfirmed, by mechanism)

1. **neru** — the only component that *synthesizes* pointer events through its own evdev proxy; a
   leaked press or a warp that is never released looks exactly like a stuck cursor. It already logs
   `ERROR app.evdev: Failed to initialize Wayland xkb_state` and two
   `WARN ... keyboard layout is not in the compositor's keymap` lines per session.
1. **ydotoold + kanata** — the documented failure mode: on 2026-09-11 an agent ran
   `ydotool click 0x40` (down only) and left the left button held for 18 hours while Hyprland
   swallowed every real click. Release with `ydotool click 0x80`, or
   `systemctl --user restart ydotoold.service`.
1. **overview plugins** (hyprexpo / GloView / hymission) — they grab the pointer while open; a grab
   that is not released on close reads as "the cursor does nothing".
1. **pleamar ↔ Hyprland shape conflict**
   ([hyprwm/Hyprland#14906](https://github.com/hyprwm/Hyprland/issues/14906)) — only if the symptom
   is the *shape* (wrong icon, vanishing pointer over a drawer). The escape hatch
   `PLEAMAR_NO_CURSOR_SHAPES=1` exists but is deliberately unset
   (`modules/user/nix-maid/gui/pleamar.nix:266-274`): with it the pointer disappears over pleamar's
   own surfaces.

## How to pin it down next time

Distinguish the three failure shapes first — they have different owners:

- `hyprctl cursorpos` a few times: coordinates moving but actions dead → button/grab problem
  (suspects 1–3); coordinates frozen → the pointer is not being delivered at all.
- `sudo libinput debug-events` (or `wev`): is a release event missing, or is the press synthetic?
- `journalctl --user -u neru -u ydotoold -u kanata -f` while reproducing.
- `hyprctl getoption plugin:dynamic_cursors:enabled` and `hyprctl plugin list` to confirm which
  overlay plugins are loaded.
- Note *when* it happens: after an overview, after neru navigation, after unlock, after a wallpaper
  change (the theme pipeline restarts scenes), or after a `pleamar-health` probe (every 2 min).

## Open questions

- Which of the three symptoms is it, and what precedes it?
- Does it ever happen with neru stopped (`systemctl --user stop neru`)?
- Did it start with a pleamar/neru/Hyprland bump?
