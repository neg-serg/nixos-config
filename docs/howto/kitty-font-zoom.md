# kitty: font size follows the window size

> Status: **implemented** — `files/kitty/font_zoom.py` (a kitty *watcher*), enabled by
> `watcher font_zoom.py` in `files/kitty/kitty.conf`, deployed as `~/.config/kitty/font_zoom.py`.
> Manual zoom: per-window hotkeys + `ctrl+super+wheel` via Hyprland.

## Problem

kitty has no "zoom out the font when the window shrinks" option. `font_size` is fixed and a smaller
OS window simply shows fewer cells — the layout (columns/rows) is lost on every resize, so a
half-width terminal re-wraps everything.

## How it works

`font_zoom.py` is a [watcher](https://sw.kovidgoyal.net/kitty/conf/#opt-watcher), not a kitten: the
`watcher` option loads a Python file into the kitty process and calls
`on_resize(boss, window, data)` whenever a window's cell count changes (i.e. on every OS window
resize, and on font changes).

- On the first events after startup the watcher only records an **anchor**: the OS window pixel size
  and the font size in effect. `STARTUP_SETTLE` (1.5 s) keeps the window manager's initial tiling
  out of the math, so a fresh terminal always starts at the configured `font_size` (12 pt).
- Every later resize sets `font_size = anchor_font * sqrt(area / anchor_area)` — the geometric mean
  of both axes, so stretching a window in one direction alone does not give a huge/tiny font.
- The result is clamped to `[MIN_FONT_SIZE, MAX_FONT_FACTOR * anchor_font]` (6 pt … 24 pt at the
  defaults), rounded to quarter points, and applied only if it differs by ≥ `DEADZONE` (0.25 pt).
- `SELF_CHANGE_GRACE` (0.15 s) drops resize events caused by kitty reacting to our own font change.
  That plus the deadzone is what keeps `font change → cell count change → on_resize` from looping.
- The font size is applied per OS window through `boss._change_font_size({os_window_id: size})`
  (`kitty @ set-font-size` has no `--match`, it can only hit the *active* OS window).
- **Manual changes win.** A font size change at an unchanged window size cannot come from a resize,
  so it must be user input (zoom hotkey, wheel, reset, `change_font_size all` from a sibling OS
  window): the watcher adopts it as the new anchor instead of scaling it back. `SIZE_SLOP` (2 %)
  absorbs the pixel jitter a WM may add while re-laying-out a window after a font change.

Kitty-side caveat that is not fixable from a watcher: the font size is per **OS window**, so
resizing a single split rescales the whole OS window too.

## Hotkeys

Per OS window (in `files/kitty/key.conf`). The `all`/`current` token is mandatory for
`change_font_size`, and `all` also rewrites the default size for *new* OS windows:

| Hotkey                                               | Action                                               |
| ---------------------------------------------------- | ---------------------------------------------------- |
| `ctrl+shift+equal`                                   | `change_font_size current +0.5`                      |
| `ctrl+shift+minus`                                   | `change_font_size current -0.5`                      |
| `ctrl+shift+0`                                       | `change_font_size current 0` — this window's default |
| `ctrl+equal` / `ctrl+minus` / `ctrl+shift+backspace` | the same, for `all` OS windows                       |

Because of the manual-change rule above, a zoom (or the reset) survives every later resize: the
anchor simply moves to "current size + current font".

## Wheel (`ctrl+super+wheel`)

kitty *cannot* map scroll events: `scroll_event()` in `kitty/mouse.c` bypasses `mouse_map`
completely (the only button names it knows are `left`/`middle`/`right`/`b4…b8`), so `mouse_map` +
wheel does not exist. The wheel is therefore caught in Hyprland and forwarded to the focused
window's kitty socket:

- binds in `files/gui/hypr/hyprland.lua`: `SUPER+CTRL+wheel up/down` → `kitty-font-zoom up|down`,
  `SUPER+CTRL+middle click` → `kitty-font-zoom reset`;
- `packages/local-bin/bin/kitty-font-zoom` (→ `~/.local/bin`): reads the focused window from
  `hyprctl activewindow -j`, and if `/tmp/kitty-<pid>` is a socket (i.e. the window is kitty), calls
  `kitten @ --to unix:/tmp/kitty-<pid> set-font-size -- <±0.5|0>`. Non-kitty windows have no such
  socket and are silently ignored;
- why the socket name works: a config-file `listen_on unix:/tmp/kitty` gets `-{kitty_pid}` appended
  by `expand_listen_on()` (`kitty/main.py`), and the pid Hyprland reports for the window *is* the
  kitty process pid.

## Pause: back to the fixed font

In a running kitty process the watcher cannot be unloaded (`watcher` is read at window creation and
`load_config_file` does not detach it), so the watcher itself has an off switch: the `font_zoom`
user variable. Paused means the plain kitty behaviour — the font size goes back to the configured
value and stops following the window. Three equivalent triggers:

- `SUPER+CTRL+Z` → `kitty-font-zoom toggle` (the same script as the wheel);

- explicit: `kitty-font-zoom off` / `kitty-font-zoom on` (also:
  `kitten @ set-user-vars font_zoom=off`);

- from inside the window, with no WM involved — kitty parses `OSC 1337` user variables:

  ```sh
  printf '\033]1337;SetUserVar=font_zoom=%s\007' "$(printf off | base64)"
  printf '\033]1337;SetUserVar=font_zoom=%s\007' "$(printf on | base64)"
  ```

`off` is `change_font_size current 0` plus "no more following"; `on` re-anchors to "current size +
current font", so following resumes from wherever the window is now. The state is per **OS window**
(the granularity of the font size itself) and lives in the kitty process, so restarting kitty clears
it — as does removing the `watcher` line from `kitty.conf` for good.

## Verification

Reproduced on Hyprland 0.56.2 (DP-2, scale 2), kitty 0.48.2. Cell width `px / columns` is the
observable: it is proportional to the font size and is reported by `kitten @ ls`.

```sh
kitty --config NONE -o font_size=12 -o listen_on=unix:/tmp/kitty-zt \
      -o allow_remote_control=yes -o watcher=/etc/nixos/files/kitty/font_zoom.py --title zt
S=unix:$(ls /tmp/kitty-zt-*)             # kitty appends its PID to the socket name
kitten @ --to $S ls | jq '.[0].tabs[0].windows[0] | {columns, lines}'
A=$(hyprctl clients -j | jq -r '.[] | select(.title=="zt") | .address')
hyprctl dispatch "hl.dsp.window.float({window=\"address:$A\", action=\"on\"})"
hyprctl dispatch "hl.dsp.window.resize({window=\"address:$A\", x=700, y=500, relative=false})"
# same code path the wheel hotkey uses:
kitten @ --to $S set-font-size -- +0.5    # / -- 0 to reset
```

Measured (logical pixels; 8.00 px/cell = the 12 pt default at this scale; cells are quantized to
whole device pixels, so the implied font size is accurate to about ±0.3 pt):

| step                              | px        | px/cell | implied font                                |
| --------------------------------- | --------- | ------- | ------------------------------------------- |
| baseline                          | 1152x1055 | 8.00    | 12 pt                                       |
| resize                            | 700x500   | 4.52    | ~6.5 pt                                     |
| resize                            | 400x300   | 4.00    | 6 pt (lower clamp)                          |
| resize back up                    | 900x700   | 6.00    | ~9 pt                                       |
| `set-font-size +0.5` (wheel path) | 1920x1055 | 8.53    | ~12.8 pt, and it sticks                     |
| resize after that zoom            | 500x400   | 4.50    | ~6.8 pt (scaled from the zoom, not from 12) |
| reset, then grow                  | 1200x900  | 16.00   | 24 pt (upper clamp)                         |

Columns stay in the same ballpark while the font shrinks with the window — i.e. the resize preserves
the layout instead of re-wrapping it — and a manual zoom (hotkey or wheel) moves the baseline
instead of being reverted by the next resize.

## Tuning

Constants live at the top of `files/kitty/font_zoom.py`: `MIN_FONT_SIZE`, `MAX_FONT_FACTOR`,
`DEADZONE`, `SELF_CHANGE_GRACE`, `STARTUP_SETTLE`, `SIZE_SLOP`. Changing them requires a rebuild
(`nh os switch /etc/nixos#odin`) plus a **kitty restart**: watchers are loaded per process, and
`load_config_file` only affects windows created afterwards.
