# player-proto — startup probe for the player UI

Scratch prototype behind the "player start time" question: how long does it take from `execve` to
the first *useful* presented frame with the proposed stack (winit + ash + cosmic-text, no GUI
framework).

This directory is gitignored (`/prototypes/` in the repo's `.gitignore`): it is a measurement rig,
not part of the NixOS configuration.

## What it does

- winit window -> Wayland surface -> `ash` instance/device/swapchain (Vulkan 1.2 baseline, no
  dynamic rendering, no sync2, single in-flight frame, FIFO present).
- One quad renderer with two fragment branches: solid rects and alpha-masked glyph quads sampling a
  CPU-built 2048x1024 R8 glyph atlas (cosmic-text shaping + swash rasterizer).
- The "useful frame" is a header row, a now-playing block and a bar graph — i.e. real text through
  the real text path, not a clear-only window.
- Every stage is stamped twice: `main+ms` (since `main`) and `process+ms`, where the latter is the
  exact process age from `/proc/self/stat` starttime vs `CLOCK_BOOTTIME`. The headline number is
  `first_present` in the `process+ms` column: it includes dynamic linking, LLVM driver init and
  everything else that `main+ms` hides.

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
./dumpframe.sh --size=1440x900 --scale=1 --shot-after=200   # real window at 1x -> /tmp/frame.ppm
./dumpframe.sh --size=1440x900 --scale=2 --shot-after=200   # same layout, 2x device pixels
```

A `--shot-after`/`--shot`/`PLAYER_DUMP_SWAPCHAIN` run always ends by itself: the capture is taken
at that frame and the app exits a couple of frames later, so a script never has to kill the player
(killing it has taken the compositor down before). `--scale=N` pins the device scale and `--size`
is then the logical layout size, which is what makes a 1x and a 2x capture comparable.

## NixOS gotchas this prototype hit (all measured)

- **No `ld.so.cache`.** winit dlopens `libwayland-client`/`libxkbcommon`, ash dlopens `libvulkan`;
  none of them resolve by plain soname for an unwrapped binary. `run.sh` reconstructs the paths
  (vulkaninfo's `RUNPATH` + the 64-bit `libxkbcommon` in the store — the store also holds a 32-bit
  copy, which fails with `ELFCLASS32`).
- **A stray `LD_LIBRARY_PATH` in the environment breaks unrelated binaries.** With
  `LD_LIBRARY_PATH=/nix/store/...glibc-2.44/lib:...gcc-16.2.0-lib/lib` both `cargo` (rustup
  toolchain) and `glslc` die with `symbol lookup error: __pointer_chk_guard, version GLIBC_PRIVATE`.
  Clear the variable for Rust/shaderc builds; the repo's own session value (`glib` only) is
  harmless.
- **GPU access is unavailable inside the agent shell** (`/dev/dri/renderD128` is world-rw but
  `open()` returns `EPERM`, also under `systemd-run --user`), so `vulkaninfo` and this probe fall
  back to llvmpipe. Correctness can be verified here; **timings must be taken in the real session**.

## player — rmpc-like MPD frontend

`cargo build --release` produces two binaries: `player-proto` (the startup probe above) and `player`
(the UI). The library crate `player_proto` holds the shared pieces: `gpu` (Vulkan, three pipelines),
`scene` (vertex format + batching + atlas), `text` (cosmic-text shaping), `mpd` (protocol client)
and `cover` (FLAC/ID3 album art).

Design tokens live in `src/theme.rs`: `Theme` (surfaces, text tones, accent pair, states), `TYPE` (a
~1.2 modular scale anchored at 13 px) and `GEOM` (spacing, radii, row pitch, row inset, index gutter,
accent rail, and the `stack`/`inner` rhythm every vertical block in the app is spaced with). Two
variants ship, `dark` (default) and `warm`, switchable at runtime with `t` or at
launch with `--theme=warm`. One face carries everything: the user's Iosevka build
(`~/.local/share/fonts/iosevka-neg`, Regular/Medium/Bold), registered by absolute path through
`FontSystem::new_with_fonts` so the nix-store Iosevka of the same family name is never picked, with a
fallback chain to DejaVu. Iosevka is monospaced, so digits in the index and duration columns line up
without a second family. Colours are authored as sRGB and linearised on the CPU (`scene::linear`)
because the swapchain is an SRGB format — without that step the driver encodes them twice and the
whole UI looks washed out.

Rows share one grid (`row::surface` / `row::text_x`): a surface inset `GEOM.row_inset` from the pane
edge with a `GEOM.row_gap` gap between rows, then an index column of `GEOM.gutter` (digits in mono at
the faintest ink — position is navigation aid, not content), then the title, then a trailing column
(duration, or a chevron for directories). The title is the only bright ink; the secondary line and
the trailing column step down to `text_faint`. The cursor draws a vertical gradient wash
(`selection` → `selection_edge`) plus a `GEOM.rail_w` accent rail, the playing row gets a weaker flat
wash (`playing_bg`) with a thin rail, and a playing queue row trades its index for an animated
equaliser. A row under the pointer gets the weakest of the three washes (`hover` → `hover_edge`),
painted under the other two, so the hierarchy plain → hover → playing → cursor holds on every
surface. The library, the queue, the search results and the three name pickers all use that one
grid, so the panes read as one system.

Layout: top bar with tabs and MPD state, left library pane with incremental filtering (one-line rows
in every window size), centre queue (or search results) with a two-line title/artist row, plus
scrollbar; right now-playing panel; bottom hint bar. The pane that owns the keyboard is raised: it
paints `Theme::pane_raised` (a lighter surface, a deeper shadow) while the panes at rest stay on
`pane_rest`, so focus is readable from the pane body and not only from an outline. The centre pane
adds a 1 px accent ring while it shows a *list* (the pickers, search), drawn under the panel so only
its edge shows. Responsive: below 1080 px the library pane is dropped — and with it the only view
whose keys act on the left, so the centre keeps the keyboard in every view — below 820 px the
now-playing panel moves into the status bar.

The now-playing panel is the frame's anchor and is drawn as one *measured* vertical stack: album art
→ title/artist/album (with the queue position riding the album line) → progress with knob and
timestamps → transport → volume → mode chips → next-up card → stream-format footer under a hairline.
Block heights are derived from `TYPE`, gaps from `GEOM.stack`/`GEOM.inner`, and the stack is measured
before anything is drawn, then centred in the panel. That buys three things: the art has equal air
left/right (it is a square centred in the inner column) and equal air above/below the stack at any
window size; a short window shrinks the art and then drops the next-up card and finally the chips
instead of pushing the transport out of the panel; and the hierarchy is explicit — the play button is
the only filled accent shape, the title is the only `text`-bright line (artist `text_dim`, album and
counter `text_faint`). The next-up block is not a label floating at the bottom any more: it is an
inset card carrying the same accent rail the list rows use, so it reads as a row that is coming.

Pointer: every frame emits a list of hit rectangles (`self.hits`) in logical units, and the pointer
position is stored in the same space (winit reports physical pixels, the event divides by the layout
scale), so hover and clicks resolve against the rectangles the user is actually looking at. Hover is
one function over the previous frame's list, which keeps it from pointing at something undrawn, and
clicks reuse the same lookup. Each target has its own state: rows take the `hover` wash, inactive
tabs the same wash inside their pill with `text` ink, prev/next a faint disc plus brighter glyphs,
off chips a lift to readable ink (on chips keep their accent), the progress and volume bars a lifted
bed (`hover_well`), a thumb at the current level and — for volume — a 2 px taller track, output rows
a wash on the list panel, and the play button a 2 px `accent_soft` ring because it is already the
accent fill and cannot signal hover with another wash. The outputs overlay emits a full-window
`CloseOverlay` rectangle under its panel, so the dim layer swallows the pointer instead of letting a
click act on the row behind it. Hovering never changes the selection.

Panes: Queue, Library (directories), **Artists**, **Albums**, **Playlists**, Search — the name lists
come from MPD `list Artist`, `list Album` and `listplaylists`, and `enter` on a name plays that
collection (`find Artist "X"` / `find Album "X"` / `listplaylistinfo X`, each song appended with
`addid` and the first one started with `playid`, so the queue is never cleared). `space` enqueues
instead of playing. **Outputs** (`o`) is a modal list backed by the `outputs` command with
`enableoutput`/`disableoutput`; each row is two lines, the configured name over the metadata that
tells two outputs apart (`pulse · pipewire · hw:0,0`). The plugin and driver come from the `outputs`
reply (MPD 0.22+); the device path only lives in the daemon's config, so it is read from `config`
and the second line simply carries the parts the daemon was willing to share — a daemon that
refuses that command to a non-local client, as MPD does by default, still shows its plugin.
Metadata the daemon repeats (`plugin` and `driver` are the same word on 0.22/0.23) is printed
once.

Queue edits and playlists: `J`/`K` reorder the queue (`move`, the cursor follows the row and the
worker refetches because `playlistlength` does not change), `d` deletes a row and `C` clears the
queue (both after a confirming second press), `a` starts "add this song to a playlist" — the
Playlists pane then acts as the chooser, `enter` appends via `playlistadd`. The Playlists pane also
manages the lists it shows without leaving the keyboard: `c` names a new playlist saved from the
current queue (`save`), `e` renames the list under the cursor (`rename`), `d` deletes it (same
second-press confirmation, and it is the *playlist* that goes, never a queue row), and `A` appends
the now-playing song to it (`playlistadd`). The three name prompts reuse the command line's editing
mode, so typing, backspace and `esc` behave as they do after `:`; the keys are scoped to the
Playlists pane. `<C-s>` opens the command line pre-filled with `save `, and `:save NAME`,
`:renameplaylist OLD NEW`, `:rmplaylist NAME` reach the same commands from the line (the list
refreshes after every edit).

Command line completion: `:` is completed, not remembered. The popup above the line lists the
vocabulary while it is still being typed (`:r` offers resume, repeat, random, rmplaylist,
renameplaylist) with a one-line description each, and `Tab` writes the highlighted candidate into
the line; pressing it again walks the list, `Shift-Tab` walks backwards. A command whose value is
something the app already holds completes that value too: `:theme <Tab>` offers `dark`/`warm`,
`:zoom <Tab>` offers `reset`, and `:rmplaylist <Tab>` / `:renameplaylist <Tab>` offer the playlist
names the daemon reported (the pane does not have to be visited first — opening `:` asks for the
list). Typing a character after a completion re-scopes the popup to the new prefix, and the three
name prompts in the Playlists pane complete the same way, since they borrow the line's editing mode.

Interface zoom: `ctrl+=` / `ctrl+-` step the scale by five points and `ctrl+0` resets it; the same
values come from `:zoom 125`, `:zoom +5`, `:zoom -5` and `:zoom reset`. The zoom multiplies the
device scale, so the layout is authored in its usual logical units at every zoom level, the
snapping grid (`physical / logical`) keeps every edge on a whole device pixel, and the fact that a
bigger zoom means a smaller logical canvas is what reflows the panes (rows go compact, the library
pane can drop out) exactly as a smaller window would. The value is remembered between runs in
`$XDG_STATE_HOME/player-proto/ui.conf`, written atomically on every change; `--zoom=N` overrides
it for one run and any pinned capture (`--render-size`/`--shot`/`--shot-seq`/`--bench`) ignores the
stored value, so a reference frame never depends on the user's preference. `PLAYER_UI_STATE` points
the store at another file, which is what the test suite uses.

Queue filter: `/` inside the queue pane narrows the rows in place instead of opening the search
pane (everywhere else `/` still does that, and `?` reaches the search pane from the queue). It is a
state of one pane, not a mode: the keys keep the mode line at `normal`, `esc` leaves *and* clears,
`enter` keeps the filter and hands the keys back, and `backspace` edits. The filter matches the
title and the artist of a row, the motions (`j`/`k`, `g`/`G`, the wheel) walk the matching rows
only, and `J`/`K` swap with the neighbour the user can see. Everything the pane *acts* on stays a
real queue index: the gutter keeps printing the row's position in the queue (a filter of "w" shows
`03`, not `01`), `enter` sends `play 2` rather than `play 0`, and the playing-row marker still
finds its track. The header carries the filter text with a caret while typing and swaps its
counter to `matches/total`, so the pane always says how much of the queue is hidden; a filter that
hides every row draws a "nothing matched" note plus the key that undoes it, which is a different
sentence from an empty queue on purpose.

ncmpcpp parity: the rmpc keymap above is the habit, and the keys rmpc never had are here under
the letters ncmpcpp uses for them, chosen so nothing already bound moves. `h`/`l` seek ∓5 s (the
design has no side-by-side panes for them to move between), `+` is a second volume-up, `x` flips
crossfade between off and the last value used (`X` walks it up by two seconds to 20), `Y` cycles
replay gain off → track → album → auto, `Z` shuffles the queue, `M` mutes and restores, `T` turns
add mode on: `enter`/`space` then append collections and library songs instead of replacing the
queue with them (the footer chip says which), `S` saves the queue under a typed name, `'` jumps to
the playing track from any pane, `@` opens the daemon's counters, and the outputs overlay answers
`a` (enable all) and `!` (disable all) besides `enter` on a row. The same actions are reachable
from the line, spelled the way ncmpcpp's console spells them: `:seek <N|+N|-N|N%>`,
`:vol <N|+N|-N>` (relative steps are *steps*: `:vol +5` raises, it does not set 5 %),
`:toggle repeat|random|single|consume`, `:crossfade <0..20>`, `:gain <off|track|album|auto>`,
`:shuffle`, `:prio <0..255>`, `:update`, `:rescan`, `:stats`, `:load <playlist>`, `:add <uri>`,
`:screen <queue|library|artists|albums|playlists|search>`, and arguments are read to the end of the
line, so a playlist name or a query may contain spaces.

Two screens need no daemon at all. `F12` (or `:clock`) opens the clock: local time, the date and a
stopwatch that `space` starts and stops, drawn over a dimmed frame so it reads as a screen of its
own; `esc` closes it. `@` (or `:stats`) opens the daemon's counters — artists, albums, tracks,
uptime, play time, database size and age — in the same kind of panel, refreshed on every press.
Both ask for nothing the player does not already hold, which is why they also work with an MPD that
is down.

Mouse: tabs, rows (single click selects, double click plays), transport buttons, mode chips, the
progress bar (click seeks) and the volume bar (click sets 0-100 %) are all hit-tested from the
previous frame's rectangles — `draw_ui` records them into a `Vec<HitArea>` as it emits geometry.
Wheel scrolls the active list.

Keyboard model (rmpc habits, four modes):

| mode    | enter       | leaves with     | what it does                                                                              |
| ------- | ----------- | --------------- | ----------------------------------------------------------------------------------------- |
| normal  | default     | —               | navigation, playback, pane switching                                                      |
| search  | `/`         | `esc` / `enter` | types into the MPD search buffer                                                          |
| command | `:`         | `esc` / `enter` | `:play N`, `:pause`, `:resume`, `:next`, `:prev`, `:stop`, `:seek N`, `:vol N`, \`:repeat |
| help    | `?` or `F1` | any key         | overlay generated from the same `KEYMAP` table the handler uses                           |

A numeric prefix multiplies the next motion (`3j`, `2ctrl+d`), vim-style.

Keys follow the user's own rmpc keymap (`~/.config/rmpc/config.ron`), including its Cyrillic
duplicates, so muscle memory carries over:

| keys                                                                  | action                                                                  |
| --------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| `j` `k` `g` `G` `ctrl+d` `ctrl+u` `ctrl+n` `ctrl+p` `ctrl+a` `ctrl+e` | list navigation (numeric prefix works: `3j`)                            |
| `tab` / `shift+tab`, `1` `0`                                          | switch pane: queue / library / search                                   |
| `enter`                                                               | play selected · enter a directory                                       |
| `p` `s` `>` `<` `f` `b` `=` `-`                                       | pause · stop · next/prev track · ±5 s · volume                          |
| `space`                                                               | queue: jump to the playing track · library: enqueue                     |
| `z` `r` `y` `R`                                                       | repeat · random · single · consume                                      |
| `d` `C`                                                               | delete selected row · clear queue (both need a second press within 3 s) |
| `c` `e` `A`                                                           | playlists: save the queue as · rename · add the playing track           |
| `/` `:` `w`                                                           | search (in the queue: filter its rows) · command line · help            |
| `esc`                                                                 | drop the queue filter · come back to the queue                          |
| `u` `U`                                                               | re-read the library                                                     |
| `t`                                                                   | cycle the theme (this app's addition, not rmpc)                         |
| `q`                                                                   | quit                                                                    |

rmpc keys with no counterpart here are reported as a toast rather than silently ignored (`2` =
Artists tab).

`./keys-test.sh` asserts the state machine end to end: tokens go through `apply_token` →
`handle_key_spec` (the same path as a real keyboard), the MPD worker runs with `PLAYER_DRY_RUN=1` so
playback is never touched, and 93 checks cover selection, tab cycling, search mode, command
execution, help, the count prefix and clamping at the end of the list, which pane is raised, what
the pointer hovers, the playlist commands the pane's own keys emit, the three list states, the
outputs metadata, the queue filter (text, match count, `nomatch`, and the *real* index the pane
plays) and the golden frames. The hover checks are geometry-driven rather than coordinate-driven:
one run dumps the frame's hit rectangles (`PLAYER_DUMP_HITS=1`) and the next run walks the pointer
through the middle of the rectangles the test picked, asserting the `hover=` field of every state
dump.

"Empty" needs a server that answers with nothing, so one run in the test talks to `stub-mpd.py`, a
stand-in that speaks the protocol and holds no artists, albums, playlists or outputs, and delays its
list replies by 120 ms. That makes both halves of the pair observable in one run: the immediate dump
of a pane key still reads `loading` and a later one reads `empty`, which is what proves the panes no
longer print the loading hint forever and that the outputs overlay has a state of its own. The same
words are exposed in every state dump (`artists=`, `albums=`, `playlists=`, `outs=`), each one of
`loading`, `empty` or `filled`.

The same stub in `--outputs` mode answers with three configured outputs — a modern one, one shaped
like a daemon older than 0.22, and one whose plugin repeats its driver — and with a `config` reply
carrying the device paths, while the default mode keeps refusing `config` the way a real MPD refuses
it. Both branches are therefore asserted without pixels: every state dump carries one
`outN='name|plugin|driver|device|second line'` field per output, and the live daemon run covers the
third case, a daemon that shares its plugin but refuses its config.

A fourth mode, `--queue`, publishes six tracks whose titles and artists start with different
letters, which is what makes the queue filter testable: a one-letter filter matches exactly one row,
so `qmatch=1` and `sel=2` together prove the pane filtered without renumbering, and the dry-run log
proves `enter` played queue index 2 and not index 0. The same run types `q` into the filter, which
would quit the player if the pane did not own the keys while it is collecting characters.

The golden frames are the layout contract: `golden/queue-1440x900-s1.ppm.gz` and
`golden/queue-2880x1800-s2.ppm.gz` are two captures of one layout at two device scales, taken
through the offscreen `--shot` path against the `--queue` stub (whose `state: stop` keeps the frame
still — no equaliser, no progress, no elapsed digits). The comparison is per region and reports the
normalised RMSE of the area that moved: top bar, connection status, library pane, queue pane,
now-playing pane and footer, plus the whole frame, which covers the gaps between them. The regions
stop short of the connection pulse dot in the top-right corner; that dot is the only live pixel in
the frame and is left to the whole-frame tolerance. Regenerate the pair only when the change to the
layout is the point: `./keys-test.sh --update-golden` rewrites both references and then compares
against them. The references are gzip-compressed PPM dumps (39 KB and 96 KB) committed despite the
repo-wide `*.gz` ignore rule, which `prototypes/player-proto/.gitignore` re-includes for `golden/`.

MPD: `player --mpd=127.0.0.1:6600` (default). A worker thread polls `status`/`currentsong` every 300
ms and refetches the queue when `playlistlength` changes, so the UI never blocks on the socket.
Album art is read straight from the file: MPD's `albumart` answers in 8 KiB chunks and stalls on the
second chunk, so `cover::embedded_picture` parses the FLAC PICTURE block (or ID3 APIC) instead — one
open() instead of a socket round trip per chunk.

Verification without a live keyboard or a compositor:

```sh
PLAYER_DRY_RUN=1 ./run.sh --render-size=1440x900 --shot-seq=/tmp/seq --keys=down,down,tab,space
./run.sh --bench=300 --render-size=1440x900      # frame cost of the full UI
```

`--keys=` drives the same keyboard state machine as real input (`handle_key_spec`), writing one PPM
per step; `PLAYER_DRY_RUN=1` makes the worker print what it *would* send to MPD instead of changing
the user's playback. A `cursor:XxY` token moves the pointer instead of pressing a key (`--cursor=X,Y`
does the same once, at startup), so one run can walk the pointer across several targets; `x` is the
separator because `--keys` already splits on commas. Real-session variants live in `real-seq.sh` /
`real-ui.sh`, which are launched from Hyprland (`hyprctl dispatch 'hl.dsp.exec_cmd(...)'`) because
the agent sandbox cannot open `/dev/dri`.

Measured on RADV (RX 9070 XT), 1440x900, full UI: 13500 vertices, 34 batches, **p50 0.132 ms/frame**
(p95 0.166). On llvmpipe the same frame costs 1.13 ms. Captures from both drivers differ by RMSE
0.078, concentrated on glyph antialiasing (sRGB blending), not layout.

Bugs this exercise found on the real GPU (both invisible on llvmpipe's tolerance):

- Re-using the frame's command buffer for an offscreen capture → `VK_ERROR_DEVICE_LOST` on RADV.
  Captures now use a dedicated command buffer and wait for the in-flight fence first.
- The offscreen image was created with a format different from the render pass attachment and the
  copy barrier declared `COLOR_ATTACHMENT_OPTIMAL` while the pass ends in `PRESENT_SRC_KHR`;
  llvmpipe answered with a SIGSEGV inside `util_copy_rect`. The image now matches the swapchain
  format and the barrier uses the real layout.

Fonts and the palette were chosen from a measured audit of this host, recorded in
`FONTS-AND-THEME.md`: Inter (400/500/600) for text, JetBrains Mono Nerd Font for digits (0.600 em,
so timers stop jittering), DejaVu Sans for the geometric symbols Inter and JetBrains lack. The audit
also found the reason the UI looked inconsistent before:
`/etc/fonts/conf.d/52-nixos-default-fonts.conf` aliases `sans-serif`, `serif` **and** `monospace` to
Iosevka, and cosmic-text resolves generic families through fontconfig, so every string was rendered
in a monospace face. The palette moved to contrast-checked values (`TEXT_3 #7F8DA0` is 5.2:1 on
`panel`; the previous `#5A6576` was 3.1:1 and failed AA on every 11 px label).

### Fuzzy finding with lusty

`F` opens a finder over the MPD music root. The rows are produced by the user's own `lusty`
binary in its non-interactive mode (`lusty --list <root> --depth 2 --query Q`), so the ranking is
the one they already use for files instead of a second, weaker matcher in the player. Typing
narrows the query (each keystroke is a separate `--list` run on a worker thread, and answers carry
a generation number so a slow reply cannot overwrite a newer one), `j`/`k` move, `enter` appends
the picked album or file with `add "<uri>"` — the queue is never cleared — and `esc` closes.

The root comes from the same probe the cover reader uses (`MPD_MUSIC_DIR`, `~/music`, `~/Music`,
`/music`, `/var/lib/mpd/music`), because MPD refuses `config` for non-local clients.

### Running it

`launch-live.sh` is the only supported entry point: NixOS has no `ld.so.cache`, so it builds
`LD_LIBRARY_PATH` from `libs.sh` (vulkaninfo's RUNPATH minus the glibc/gcc entries, plus the 64-bit
`libxkbcommon`) and **preflight-checks** that `libwayland-client`, `libxkbcommon` and `libvulkan`
actually dlopen before exec'ing the binary. A dirty `.libs` therefore produces a readable diagnosis
instead of winit's `NoWaylandLib` panic: the launcher prints one line per library (`ok` /
`FAIL <lib>: <reason>`) plus the command that rebuilds the cache.

The player also survives a missing compositor: instead of panicking it prints which of
`WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR` and the socket is wrong.

### Display scaling

The UI is authored in logical units: every frame the layout size is
`swapchain extent / scale factor`, and that same logical size is handed to the vertex shader as its
resolution, so the geometry always covers the whole surface (a 4K panel at scale 2 gets 2x bigger
glyphs, not a quarter-size UI in the corner). `Resized` and `ScaleFactorChanged` recreate the
swapchain (debounced to 200 ms, and skipped when the new size is within 2 px),
`SUBOPTIMAL`/`OUT_OF_DATE` from acquire/present trigger the same rebuild, and the compositor's
`currentExtent` wins over the window size, which stops the tiling-vs-buffer size feedback loop.

### Layout invariants

`./invariants.sh` (1440x900 by default, `SIZE=WxH` to override) asserts the composition contract
from the rectangles `draw_ui` records under `PLAYER_RECTS`/`PLAYER_RECTS_DUMP` — exact arithmetic,
not pixel guessing: the album art is square and centred in its column with air on both sides,
only the art is centred (everything else is left-aligned), the panes share the body band, the
top bar spans the frame, the footer is bottom-flush and full width, and the queue pane takes
either the library gutter or the freed one when the library is dropped. Each element is also cut
into its own small crop under `/tmp/player-elements/`, so one element can be judged alone.
Rows are covered too: the inset inside the pane, the index gutter before the text column, the
96 px duration column flush with the pane's right edge, and the row height following the density
breakpoint (40 px above 760 px of height, 36 below). The script already earned its keep by failing
"art keeps air on both sides" (304 px art in a 304 px column).

## Numbers so far (llvmpipe, software rasterizer — NOT a GPU result)

Startup, median over 5-7 runs, `process+ms` (age from `fork`, see the trap below):

| mark                                   | process+ms | delta |
| -------------------------------------- | ---------- | ----- |
| main (exec → loader → ctors)           | 10-15      | 10-15 |
| window created                         | 14-18      | ~3    |
| fonts_ready (FontSystem::new)          | 20-24      | ~6    |
| instance (ICD load + vkCreateInstance) | 40-46      | ~20   |
| device (vkCreateDevice)                | 70-78      | ~30   |
| pipelines (2 graphics pipelines)       | 71-79      | ~1    |
| atlas_upload (2048x1024 R8)            | 73-81      | ~2    |
| first_present                          | 120-130    | ~47   |

`./measure.sh 5`: process → first_present min 120 / med 126 / max 129 ms; `main → first_present` min
109 / med 117 / max 118 ms.

Per-frame cost, offscreen, no compositor, 300 frames after a warm-up (`--bench`):

| size      | p50      | p95      | implied fps |
| --------- | -------- | -------- | ----------- |
| 640x360   | 0.156 ms | 0.194 ms | 6415        |
| 1100x620  | 0.251 ms | 0.468 ms | 3991        |
| 1920x1080 | 0.506 ms | 0.584 ms | 1976        |

Layout cost of the whole UI text (5 strings, 116 glyph quads) via `--bench-layout 100`: **0.175 ms**
per layout, i.e. re-shaping on every track change is free.

Binary: 5.8 MB unstripped / 4.8 MB stripped, `DT_NEEDED` = libgcc_s, libm, libc, ld-linux;
libvulkan/libwayland-client/libxkbcommon are dlopened. Loader work before `main`: 3-8 ms, 310 named
\+ 12399 relative relocations.

## Measurement traps this probe found

- `/proc/self/stat` starttime is set at **fork, not exec**. A wrapper script that does work (here:
  `readelf`+`fd`+`file` over `/nix/store` to find `libxkbcommon`) is charged to the application: the
  same binary measured 240-270 ms through the naive wrapper and 120-130 ms when exec'd directly.
  `run.sh` now caches the path list in `.libs`, and `measure.sh` bypasses the wrapper entirely.
- `vkQueuePresentKHR` returning is not "shown" (see the limitation below).
- A single `hyperfine` over a launcher measures the launcher; only in-process stamps are honest.

## HDR probe (`--hdr`)

The surface on this session advertises 66 format/colorspace pairs, including
`A2R10G10B10_UNORM_PACK32` and `A2B10G10R10_UNORM_PACK32` with `HDR10_ST2084_EXT`, `HDR10_HLG_EXT`,
`BT2020_LINEAR_EXT`, `DISPLAY_P3_*`, `EXTENDED_SRGB_LINEAR_EXT`. With `--hdr` the probe creates the
swapchain as `A2R10G10B10_UNORM_PACK32` + `HDR10_ST2084_EXT` and, when the device exposes
`VK_EXT_hdr_metadata`, attaches BT2020/PQ mastering metadata (1000 nits, 400 nits frame average).
Measured here it succeeds — but through **llvmpipe**, so it proves the compositor accepts an HDR10
swapchain, not that RADV + Hyprland actually drive the panel in HDR. That still has to be run in a
real session, and should be checked against what the compositor reports for the output (Hyprland
`render:cm_enabled=true`, `cm_auto_hdr` unset).

## Known limitations of this probe

- No swapchain recreation, no resize handling, no vsync/pacing policy. **"Presented" here means
  `vkQueuePresentKHR` returned**, not "the compositor latched it": the honest metric needs
  `wp_presentation` feedback, which requires owning the Wayland connection — winit does not expose
  it. (A `request_redraw` round trip was tried as a proxy and is useless: the event is delivered in
  the same loop turn, 17 us after the present call.) If the real app ends up owning Wayland (SCTK)
  instead of winit, `wp_presentation` becomes available and this number gets replaced by the real
  shown-at timestamp.
- SDR only: swapchain is `B8G8R8A8_SRGB` + `SRGB_NONLINEAR`. The surface on this host does advertise
  `A2R10G10B10_UNORM_PACK32`/`A2B10G10R10_UNORM_PACK32` with `HDR10_ST2084_EXT`, `HDR10_HLG_EXT`,
  `BT2020_LINEAR_EXT` (measured through llvmpipe's Wayland WSI), but no `VK_EXT_hdr_metadata`
  handling and no PQ/HLG encode path exist yet.
- No clipping, scrolling, hit-testing, IME or animations — the parts the note correctly called the
  real GUI work.
