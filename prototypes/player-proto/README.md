# player-proto — startup probe for the player UI

Scratch prototype behind the "player start time" question: how long does it take from
`execve` to the first *useful* presented frame with the proposed stack
(winit + ash + cosmic-text, no GUI framework).

This directory is gitignored (`/prototypes/` in the repo's `.gitignore`): it is a
measurement rig, not part of the NixOS configuration.

## What it does

* winit window -> Wayland surface -> `ash` instance/device/swapchain (Vulkan 1.2 baseline,
  no dynamic rendering, no sync2, single in-flight frame, FIFO present).
* One quad renderer with two fragment branches: solid rects and alpha-masked glyph quads
  sampling a CPU-built 2048x1024 R8 glyph atlas (cosmic-text shaping + swash rasterizer).
* The "useful frame" is a header row, a now-playing block and a bar graph — i.e. real text
  through the real text path, not a clear-only window.
* Every stage is stamped twice: `main+ms` (since `main`) and `process+ms`, where the latter is
  the exact process age from `/proc/self/stat` starttime vs `CLOCK_BOOTTIME`. The headline
  number is `first_present` in the `process+ms` column: it includes dynamic linking, LLVM
  driver init and everything else that `main+ms` hides.

## Build and run

```sh
nix run nixpkgs#glslc -- --version 2>/dev/null || true   # only needed to rebuild shaders
./shaders/build.sh            # GLSL -> SPIR-V (committed .spv files are enough to build)
export CARGO_HOME=$PWD/../.cargo
cargo build --release
./run.sh --frames 1            # one frame, then exit
./measure.sh 20                # 20 runs, min/median/max for process->first_present
./run.sh --frames 1 --shot /tmp/frame.ppm   # offscreen render of the same quads, as PPM
./run.sh --frames 1 --hdr      # HDR probe: HDR10 swapchain + VK_EXT_hdr_metadata
```

## NixOS gotchas this prototype hit (all measured)

* **No `ld.so.cache`.** winit dlopens `libwayland-client`/`libxkbcommon`, ash dlopens
  `libvulkan`; none of them resolve by plain soname for an unwrapped binary. `run.sh`
  reconstructs the paths (vulkaninfo's `RUNPATH` + the 64-bit `libxkbcommon` in the store —
  the store also holds a 32-bit copy, which fails with `ELFCLASS32`).
* **A stray `LD_LIBRARY_PATH` in the environment breaks unrelated binaries.** With
  `LD_LIBRARY_PATH=/nix/store/...glibc-2.44/lib:...gcc-16.2.0-lib/lib` both `cargo`
  (rustup toolchain) and `glslc` die with
  `symbol lookup error: __pointer_chk_guard, version GLIBC_PRIVATE`. Clear the variable for
  Rust/shaderc builds; the repo's own session value (`glib` only) is harmless.
* **GPU access is unavailable inside the agent shell** (`/dev/dri/renderD128` is world-rw but
  `open()` returns `EPERM`, also under `systemd-run --user`), so `vulkaninfo` and this probe
  fall back to llvmpipe. Correctness can be verified here; **timings must be taken in the real
  session**.

## player — rmpc-like MPD frontend

`cargo build --release` produces two binaries: `player-proto` (the startup probe above) and
`player` (the UI). The library crate `player_proto` holds the shared pieces:
`gpu` (Vulkan, three pipelines), `scene` (vertex format + batching + atlas), `text` (cosmic-text
shaping), `mpd` (protocol client) and `cover` (FLAC/ID3 album art).

Design tokens live in `src/theme.rs`: `Theme` (surfaces, text tones, accent pair, states),
`TYPE` (a ~1.2 modular scale anchored at 13 px) and `GEOM` (spacing, radii, row height). Two
variants ship, `dark` (default) and `warm`, switchable at runtime with `t` or at launch with
`--theme=warm`. Fonts are explicit: Inter (Regular/Medium/SemiBold) for text and FiraCode Nerd
Font Mono for numerals, timings, indices and transport symbols, loaded through
`FontSystem::new_with_fonts` with a fallback chain to DejaVu. Colours are authored as sRGB and
linearised on the CPU (`scene::linear`) because the swapchain is an SRGB format — without that
step the driver encodes them twice and the whole UI looks washed out.

Layout: top bar with tabs and MPD state, left library pane with incremental filtering, centre
queue (or search results) with number/title/artist/duration, animated equaliser on the playing
row, selection pill and scrollbar; right now-playing panel with rounded album art + dimmed
"backdrop" wash, title (auto-shrinking before ellipsis), artist/album/track position, progress
with knob, transport, volume and mode chips; bottom hint bar. Responsive: below 1080 px the
library pane is dropped, below 820 px the now-playing panel moves into the status bar.

Panes: Queue, Library (directories), **Artists**, **Albums**, **Playlists**, Search — the name
lists come from MPD `list Artist`, `list Album` and `listplaylists`, and `enter` on a name plays
that collection (`find Artist "X"` / `find Album "X"` / `listplaylistinfo X`, each song appended
with `addid` and the first one started with `playid`, so the queue is never cleared). `space`
enqueues instead of playing. **Outputs** (`o`) is a modal list backed by the `outputs` command
with `enableoutput`/`disableoutput`.

Queue edits and playlists: `J`/`K` reorder the queue (`move`, the cursor follows the row and the
worker refetches because `playlistlength` does not change), `d` deletes a row and `C` clears the
queue (both after a confirming second press), `a` starts "add this song to a playlist" — the
Playlists pane then acts as the chooser, `enter` appends via `playlistadd`. `<C-s>` opens the
command line pre-filled with `save `, and `:save NAME`, `:renameplaylist OLD NEW`,
`:rmplaylist NAME` manage saved playlists (the list refreshes after every edit).

Mouse: tabs, rows (single click selects, double click plays), transport buttons, mode chips, the
progress bar (click seeks) and the volume bar (click sets 0-100 %) are all hit-tested from the
previous frame's rectangles — `draw_ui` records them into a `Vec<HitArea>` as it emits geometry.
Wheel scrolls the active list.

Keyboard model (rmpc habits, four modes):

| mode | enter | leaves with | what it does |
|---|---|---|---|
| normal | default | — | navigation, playback, pane switching |
| search | `/` | `esc` / `enter` | types into the MPD search buffer |
| command | `:` | `esc` / `enter` | `:play N`, `:pause`, `:resume`, `:next`, `:prev`, `:stop`, `:seek N`, `:vol N`, `:repeat|random|single|consume [on|off]`, `:theme dark|warm`, `:search Q`, `:q` |
| help | `?` or `F1` | any key | overlay generated from the same `KEYMAP` table the handler uses |

A numeric prefix multiplies the next motion (`3j`, `2ctrl+d`), vim-style.

Keys follow the user's own rmpc keymap (`~/.config/rmpc/config.ron`), including its Cyrillic
duplicates, so muscle memory carries over:

| keys | action |
|---|---|
| `j` `k` `g` `G` `ctrl+d` `ctrl+u` `ctrl+n` `ctrl+p` `ctrl+a` `ctrl+e` | list navigation (numeric prefix works: `3j`) |
| `tab` / `shift+tab`, `1` `0` | switch pane: queue / library / search |
| `enter` | play selected · enter a directory |
| `p` `s` `>` `<` `f` `b` `=` `-` | pause · stop · next/prev track · ±5 s · volume |
| `space` | queue: jump to the playing track · library: enqueue |
| `z` `r` `y` `R` | repeat · random · single · consume |
| `d` `C` | delete selected row · clear queue (both need a second press within 3 s) |
| `/` `:` `w` | search · command line · help |
| `u` `U` | re-read the library |
| `t` | cycle the theme (this app's addition, not rmpc) |
| `q` | quit |

rmpc keys with no counterpart here are reported as a toast rather than silently ignored
(`2` = Artists tab).

`./keys-test.sh` asserts the state machine end to end: tokens go through `apply_token` →
`handle_key_spec` (the same path as a real keyboard), the MPD worker runs with
`PLAYER_DRY_RUN=1` so playback is never touched, and twelve checks cover selection, tab cycling,
search mode, command execution, help, the count prefix and clamping at the end of the list.

MPD: `player --mpd=127.0.0.1:6600` (default). A worker thread polls `status`/`currentsong` every
300 ms and refetches the queue when `playlistlength` changes, so the UI never blocks on the
socket. Album art is read straight from the file: MPD's `albumart` answers in 8 KiB chunks and
stalls on the second chunk, so `cover::embedded_picture` parses the FLAC PICTURE block (or ID3
APIC) instead — one open() instead of a socket round trip per chunk.

Verification without a live keyboard or a compositor:

```sh
PLAYER_DRY_RUN=1 ./run.sh --render-size=1440x900 --shot-seq=/tmp/seq --keys=down,down,tab,space
./run.sh --bench=300 --render-size=1440x900      # frame cost of the full UI
```

`--keys=` drives the same keyboard state machine as real input (`handle_key_spec`), writing one
PPM per step; `PLAYER_DRY_RUN=1` makes the worker print what it *would* send to MPD instead of
changing the user's playback. Real-session variants live in `real-seq.sh` / `real-ui.sh`, which
are launched from Hyprland (`hyprctl dispatch 'hl.dsp.exec_cmd(...)'`) because the agent sandbox
cannot open `/dev/dri`.

Measured on RADV (RX 9070 XT), 1440x900, full UI: 13500 vertices, 34 batches,
**p50 0.132 ms/frame** (p95 0.166). On llvmpipe the same frame costs 1.13 ms. Captures from both
drivers differ by RMSE 0.078, concentrated on glyph antialiasing (sRGB blending), not layout.

Bugs this exercise found on the real GPU (both invisible on llvmpipe's tolerance):

* Re-using the frame's command buffer for an offscreen capture → `VK_ERROR_DEVICE_LOST` on RADV.
  Captures now use a dedicated command buffer and wait for the in-flight fence first.
* The offscreen image was created with a format different from the render pass attachment and the
  copy barrier declared `COLOR_ATTACHMENT_OPTIMAL` while the pass ends in `PRESENT_SRC_KHR`;
  llvmpipe answered with a SIGSEGV inside `util_copy_rect`. The image now matches the swapchain
  format and the barrier uses the real layout.

Fonts and the palette were chosen from a measured audit of this host, recorded in
`FONTS-AND-THEME.md`: Inter (400/500/600) for text, JetBrains Mono Nerd Font for digits (0.600 em,
so timers stop jittering), DejaVu Sans for the geometric symbols Inter and JetBrains lack. The
audit also found the reason the UI looked inconsistent before: `/etc/fonts/conf.d/52-nixos-default-fonts.conf`
aliases `sans-serif`, `serif` **and** `monospace` to Iosevka, and cosmic-text resolves generic
families through fontconfig, so every string was rendered in a monospace face. The palette moved to
contrast-checked values (`TEXT_3 #7F8DA0` is 5.2:1 on `panel`; the previous `#5A6576` was 3.1:1 and
failed AA on every 11 px label).

## Numbers so far (llvmpipe, software rasterizer — NOT a GPU result)

Startup, median over 5-7 runs, `process+ms` (age from `fork`, see the trap below):

| mark | process+ms | delta |
|---|---|---|
| main (exec → loader → ctors) | 10-15 | 10-15 |
| window created | 14-18 | ~3 |
| fonts_ready (FontSystem::new) | 20-24 | ~6 |
| instance (ICD load + vkCreateInstance) | 40-46 | ~20 |
| device (vkCreateDevice) | 70-78 | ~30 |
| pipelines (2 graphics pipelines) | 71-79 | ~1 |
| atlas_upload (2048x1024 R8) | 73-81 | ~2 |
| first_present | 120-130 | ~47 |

`./measure.sh 5`: process → first_present min 120 / med 126 / max 129 ms;
`main → first_present` min 109 / med 117 / max 118 ms.

Per-frame cost, offscreen, no compositor, 300 frames after a warm-up (`--bench`):

| size | p50 | p95 | implied fps |
|---|---|---|---|
| 640x360 | 0.156 ms | 0.194 ms | 6415 |
| 1100x620 | 0.251 ms | 0.468 ms | 3991 |
| 1920x1080 | 0.506 ms | 0.584 ms | 1976 |

Layout cost of the whole UI text (5 strings, 116 glyph quads) via `--bench-layout 100`:
**0.175 ms** per layout, i.e. re-shaping on every track change is free.

Binary: 5.8 MB unstripped / 4.8 MB stripped, `DT_NEEDED` = libgcc_s, libm, libc, ld-linux;
libvulkan/libwayland-client/libxkbcommon are dlopened. Loader work before `main`: 3-8 ms,
310 named + 12399 relative relocations.

## Measurement traps this probe found

* `/proc/self/stat` starttime is set at **fork, not exec**. A wrapper script that does work
  (here: `readelf`+`fd`+`file` over `/nix/store` to find `libxkbcommon`) is charged to the
  application: the same binary measured 240-270 ms through the naive wrapper and 120-130 ms
  when exec'd directly. `run.sh` now caches the path list in `.libs`, and `measure.sh` bypasses
  the wrapper entirely.
* `vkQueuePresentKHR` returning is not "shown" (see the limitation below).
* A single `hyperfine` over a launcher measures the launcher; only in-process stamps are honest.

## HDR probe (`--hdr`)

The surface on this session advertises 66 format/colorspace pairs, including
`A2R10G10B10_UNORM_PACK32` and `A2B10G10R10_UNORM_PACK32` with `HDR10_ST2084_EXT`,
`HDR10_HLG_EXT`, `BT2020_LINEAR_EXT`, `DISPLAY_P3_*`, `EXTENDED_SRGB_LINEAR_EXT`.
With `--hdr` the probe creates the swapchain as `A2R10G10B10_UNORM_PACK32` + `HDR10_ST2084_EXT`
and, when the device exposes `VK_EXT_hdr_metadata`, attaches BT2020/PQ mastering metadata
(1000 nits, 400 nits frame average). Measured here it succeeds — but through **llvmpipe**, so it
proves the compositor accepts an HDR10 swapchain, not that RADV + Hyprland actually drive the
panel in HDR. That still has to be run in a real session, and should be checked against what the
compositor reports for the output (Hyprland `render:cm_enabled=true`, `cm_auto_hdr` unset).

## Known limitations of this probe

* No swapchain recreation, no resize handling, no vsync/pacing policy. **"Presented" here means
  `vkQueuePresentKHR` returned**, not "the compositor latched it": the honest metric needs
  `wp_presentation` feedback, which requires owning the Wayland connection — winit does not
  expose it. (A `request_redraw` round trip was tried as a proxy and is useless: the event is
  delivered in the same loop turn, 17 us after the present call.) If the real app ends up owning
  Wayland (SCTK) instead of winit, `wp_presentation` becomes available and this number gets
  replaced by the real shown-at timestamp.
* SDR only: swapchain is `B8G8R8A8_SRGB` + `SRGB_NONLINEAR`. The surface on this host does
  advertise `A2R10G10B10_UNORM_PACK32`/`A2B10G10R10_UNORM_PACK32` with `HDR10_ST2084_EXT`,
  `HDR10_HLG_EXT`, `BT2020_LINEAR_EXT` (measured through llvmpipe's Wayland WSI), but no
  `VK_EXT_hdr_metadata` handling and no PQ/HLG encode path exist yet.
* No clipping, scrolling, hit-testing, IME or animations — the parts the note correctly
  called the real GUI work.
