# Night watch 2026-11-01: agents kept working, pleamar measured

Owner went to sleep at ~04:15 MSK with three herdr agent panes alive. This note is the morning
hand-off: what was armed, what was measured, what is still open, in that order.

## 1. The watch (armed, running)

`night-watch.service` (systemd user unit, `systemd-run --user --collect`, started 04:17:00):

```
systemctl --user status night-watch
tail -f /etc/nixos/.agent/tmp/night-watch.log
journalctl --user -u night-watch
systemctl --user stop night-watch        # disarm
```

Script: `.agent/tmp/night-watch.sh` (v2; the previous facts-only version is kept as
`night-watch-v1-facts-only.sh`). It polls every 60 s and does exactly two things:

- logs every state transition of the watched panes;
- on a `working -> idle` transition it counts the open items of the agent's *own* checklist in the
  pane (`✓ 3/8` header plus `├─ ○ …` rows) and, if any are still open, sends the standing
  continuation prompt through `herdr pane run`. Caps: 4 kicks per pane per run, 25 min apart.

It never approves an approval request and never kicks a pane whose list is closed — an idle agent
with nothing open is a finished agent, not a stuck one (the 2026-10-23 lesson).

Watched panes, verified with `herdr agent list` at 04:17:

| pane    | what                | state at 04:15                    | open items                      |
| ------- | ------------------- | --------------------------------- | ------------------------------- |
| w1B:p1B | vLLM ROCm agent     | working                           | 5 of 8                          |
| w1B:p13 | pleamar cursor/perf | idle (asked the owner a question) | hidden — pane showed a question |
| w1B:p15 | pleamar parity      | idle, `⛔ blocked · 12/24`        | 2 of 5                          |

Both idle panes were kicked once by hand at 04:16 because they were waiting for the owner, not for
work: the standing prompt tells an agent to write owner-only decisions into its report and keep
going on everything it *can* close. Both returned to `working` within 15 s.

## 2. Does pleamar slow the machine down? Measured: no.

Method: `CPUUsageNSec` deltas per unit over 20-30 s windows, plus a true A/B of the compositor (stop
all five scenes, measure, restart, measure).

| window           | Hyprland (one core) |
| ---------------- | ------------------- |
| scenes running   | 42.94 %             |
| scenes stopped   | 42.33 %             |
| scenes restarted | 42.69 %             |

Scenes at rest, 30 s window: bar 0.90 %, panels 0.47 %, notifications 0.40 %, toast 0.60 %, launcher
1.00 % — **3.40 % of one core total**, i.e. 0.11 % of this machine's 32 threads.

The load the owner felt at 04:12 was `python3.14 -m pytest` at 421 % of a core and
`nix build --impure -f /tmp/vllm-rocm.nix --cores 10`, both from the vLLM agent in pane w1B:p1B,
with loadavg 5-13. Hyprland's own 43 % of a core also exists with all pleamar scenes stopped, so it
is not pleamar's bill either.

What *is* real, and cheap to fix:

- the **launcher paints ~60 fps while closed**: its own log says
  `this scene does not keep up: 16.7 ms a frame against the 4.2 the screen gives`, and it costs
  exactly 1.00 % of a core with nothing on screen;
- `toast`, `panels` and `notifications` keep a 30 fps idle pace for surfaces nobody is looking at
  (0.40-0.60 % each).

Handed to the pleamar agent (w1B:p13) as its own scope, with these numbers, at 04:21 —
`.agent/tmp/night-watch.sh log` records the hand-off.

Delivered by that agent and re-measured here at 04:26, after restarting the scenes so the live
`.plm` files were read again:

| scene         | before     | after      |
| ------------- | ---------- | ---------- |
| bar           | 0.90 %     | 0.83 %     |
| panels        | 0.47 %     | 0.47 %     |
| notifications | 0.40 %     | 0.40 %     |
| toast         | 0.60 %     | 0.23 %     |
| launcher      | 1.00 %     | 0.40 %     |
| **total**     | **3.40 %** | **2.33 %** |

Commits: `49619c5c [gui/pleamar] Launcher and toast: pace the idle surfaces at 30 fps`. The launcher
now carries a 1×1 keeper surface and renders 2×2 frames at 33.3 ms (30 fps) while closed, where it
used to round at the monitor's 238 fps.

## 3. Cursor: two mechanisms, one already patched, one is a config decision

Already in the running build (pleamar 0.4.31 carries
`packages/overlays/pleamar-cursor-shape.patch`): a scene says its cursor shape again every 500 ms
while the pointer is inside it, which repairs a shape the compositor dropped. That covers
`hyprwm/Hyprland#14906` and a cursor surface that goes away with its client.

The second mechanism was still armed: `cursor:hide_on_key_press = true`
(`files/gui/hypr/hyprland.lua:245`). Any key press throws the cursor image away until the pointer
moves, and nothing re-asks for a shape while the pointer sits over a layer surface — which is the "a
scene appears and the pointer is gone" report, seen from the other end. It is a one-line runtime A/B
on this Hyprland (0.56 parses Lua, so `hyprctl keyword` is rejected):

```
hyprctl eval 'hl.config({ cursor = { hide_on_key_press = false } })'   # cursor stays while typing
hyprctl eval 'hl.config({ cursor = { hide_on_key_press = true } })'    # back to the old value
```

Both directions were run and verified with `hyprctl getoption cursor:hide_on_key_press`; the session
was then handed to the pleamar agent with this lead, and it took the decision and committed it:
`42b7e4d2 [gui/hypr] Cursor: no hide-on-key-press blanking`, live value now `bool: false`.

Delivery gap to remember: `~/.config/hypr/hyprland.lua` is **not** a live symlink into `/etc/nixos`,
it is a copy in the nix store (unlike `files/pleamar/**`), so the committed line reaches the running
compositor only with the next switch. Until then the live session keeps the value through `eval`,
which a Hyprland reload drops.

The visual confirmation (does the pointer survive a scene appearing over it?) still needs a human at
the screen: `grim` cannot be used for it on this host (every variant dies with
`failed to create buffer`, including `-c`, a region and `-s 1`), and the desktop tool's captures do
not include the pointer.

## 4. Open for the owner

- **Switch is the only blocked step.** `42b7e4d2` (cursor) lives in a nix-store copy, so it needs a
  switch to survive a compositor reload; `49619c5c` (idle pace) is already live because
  `files/pleamar/**` is live-linked. The switch was *not* run: the working tree still carries the
  vLLM agent's unfinished work (`flake.lock`, `modules/llm/default.nix`,
  `packages/overlays/dev.nix`, `modules/llm/vllm.nix`, `packages/vllm-rocm/`), and a switch would
  bake all of it in.
- The vLLM build in w1B:p1B is the reason the desktop was slow tonight, not the shell.
- `notifications` is no longer the outlier it was on 2026-10-31 (12.6 % of a core then, 0.40 % now
  after the 30 fps idle cap): it is inside its 0.5 % parity budget for the first time.
- Truth still unverified by eye: whether the pointer now survives a scene appearing over it. Both
  known wipe paths are closed (shape re-said every 500 ms; key press no longer blanks), but the
  confirmation is a human looking at the screen.

## 5. Cursor patch review and rewrite (2026-11-01, afternoon)

The owner asked for the opposite of what section 3 concluded: the shell must not ask the compositor
for a cursor shape *at all* and must take no other cursor action. That is now the default.

### What the previous patch did

Four hunks in `packages/overlays/pleamar-cursor-shape.patch`:

| where                       | what                                                                  | cost                                       |
| --------------------------- | --------------------------------------------------------------------- | ------------------------------------------ |
| `WaylandWindow::cursor()`   | `set_shape(self.serial, shape)` on every change                       | one request per surface of the scene       |
| `PointerHandler` `Enter`    | `set_shape(serial, last shape)` on every pointer entry                | one request per entry                      |
| `PointerHandler` `Leave`    | `set_shape(last serial, Shape::Default)` on the way out               | one request per exit                       |
| `render.rs` cursor decision | re-said the shape every 500 ms while the pointer was inside (`again`) | forced re-send, bypassing "only on change" |

### Measured on the wire (`WAYLAND_DEBUG=client`, one scene, pointer resting inside)

```
old build: binds wp_cursor_shape_manager_v1 = 1, set_shape = 99 in 20 s (~5/s)
new build: binds it = 0, creates no device, set_shape = 0
```

Five requests a second is more than the 500 ms pace suggests because every iteration calls
`l.cursor(wanted)` for **each sheet of the scene** (`for l in &sheets`), not once per pointer.

What it costs the compositor: nothing measurable. Over the same 20 s window Hyprland re-imported the
KMS cursor buffer **0** times with the old build — an unchanged shape is dropped on its side. So the
repair loop was protocol noise, not the lag, and the same holds for the `Leave` restore.

What it did risk: the serial it re-said with is that surface's **last `Enter` serial**, not the
current one, so the requests arrive from a client that may not hold the pointer — the exact shape of
hyprwm/Hyprland#14906, five processes poking the session's one cursor, twice a second, forever.

### What ships now (`a0597abf`, deployed in system `anhdp60pw`, unit binary `7zri6sgm`)

- `wp_cursor_shape_manager_v1` is never bound unless `PLEAMAR_CURSOR_SHAPES=1`;
- no shape on enter, no restore on leave — the renderer still computes a zone's `cursor:` (it is
  scene data), and the value goes nowhere;
- the 0.5 s repair loop is gone with its `cursor_said` state;
- `cursor:hide_on_key_press` stays `false` (`42b7e4d2`), now also deployed, so nothing blanks the
  image while typing either.

### Where the lag can come from, by code

- `rate:` on a full-screen surface: `panels.plm:125` opens a drawer at **240 fps**, the launcher's
  keeper is 240 while open, the bar runs 120 while the pointer is on the strip. Measured: opening
  the launcher raised Hyprland by ~14.5 points of one core; with all five scenes stopped Hyprland
  stays at ~42 %, so nothing pleamar does at *rest* is responsible for the floor.
- `bar.plm:620` `surface barcatcher` is a **full-monitor input region** while `tray_open`, with
  `cursor: pointer` over the whole screen. If that fact ever sticks (a scene that dies with the menu
  open, a `--say` left in a debug shell), every click on the desktop goes to the bar scene and the
  pointer is a hand everywhere — which reads exactly as "the computer is unusable".
- `hide_on_key_press` is now off, so keypress blanking is out of the picture.
