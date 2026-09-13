# Lusty: separate Rust picker (architecture)

## Goal

Replace the slow parts of LustyExplorer (the Lua port in nvim) with a separate native process while
keeping nvim as the editor. The target win is 10× or more on typing and on listing large
directories.

Measurements (headless, repo copy, /etc/nixos):

| Operation                                  | Now (Lua)         | Target (Rust)                  |
| ------------------------------------------ | ----------------- | ------------------------------ |
| list /home/neg, depth 1 (11 entries)       | 4.9 ms            | < 1 ms                         |
| list /etc/nixos, depth 2 (271 entries)     | 8.0 ms            | < 2 ms                         |
| list /nix/store, depth 1 (151,363 entries) | **4884 ms**       | < 150 ms                       |
| fuzzy.score × 5000                         | 1.2 ms            | < 0.5 ms                       |
| typing (latency)                           | nvim float redraw | native ratatui, partial redraw |

Two bottlenecks in the current Lua port:

1. **B1 — nvim float-window redraw** on every keypress (this is the "typing lags" on ordinary
   directories; the logic here is 0.1–0.2 ms per callback).
1. **B2 — synchronous listing** `vim.fn.readdir` + one `vim.fn.getftype` (stat) per file on the UI
   thread: 151k files = 4.9 s. Native `fd` does the same 151k in ~107 ms and asynchronously.

## Process model (Model 1, fzf-style)

- An nvim wrapper (`,l`/`,C`/`,B`/`,G`) opens a terminal via `termopen` and runs
  `lusty <mode> <root>`.
- The binary draws on the alternate screen (ratatui/crossterm); the user types/picks; on selection
  the binary prints an `ACTION<TAB>PATH` line to stdout and exits with code 0; cancel — code 1.
- `on_exit` in Lua reads stdout and opens the file in nvim (edit/tab/split), reusing the current
  buffer-opening logic. No RPC daemon is needed.
- Later, optionally: a persistent process + msgpack-RPC via `nvim --listen`.

## Components

1. `~/src/lusty` (flake input `lusty` in /etc/nixos) — a Rust crate (binary `lusty`):

   - `cli`: mode (files|buffers|grep), root, depth, skip-dirs, follow-mounts, dotfile flag, initial
     query.
   - `listing`: `ignore`/`walkdir` + `rayon` (parallel traversal), depth limit, skipping mount
     points (/proc/self/mountinfo), skip-dirs glob (`~`/`*`/`?`), "less nested on top" ordering.
   - `scoring`: port of `fuzzy.lua` (fzy-style) to Rust + prefix anchor on the first letter (the
     first letter of the query must be a name prefix). Mercury — optional.
   - `colors`: LS_COLORS parsing (env → dircolors file → `dircolors -b`), ANSI coloring of
     dir/symlink/ext; the same priority as in the current `ls_colors.lua`.
   - `ui`: ratatui — query line, list with incremental partial redraw, gravity (bottom by default),
     selection, RU layout (dual-mapping of physical keys to EN), the same key set.
   - `output`: on Enter/Tab/C-t/C-o/C-v prints `ACTION<TAB>PATH`.

1. `files/nvim/lua/lusty/native.lua` — a shim: `termopen` + `on_exit` + option forwarding. The old
   Lua port stays as the fallback (`g:LustyExplorerNative=0`).

## UX parity (must be preserved)

- Keys: Enter/Tab, C-t, C-o/C-v, C-n/C-p, C-f/C-b (columns), C-l (long mode with metadata), C-y
  (sort name/ext/size/time), C-u (clear), C-Space (multi-select mark in the native pickers: Enter
  opens all marked files in the filesystem/recent floats, C-d unloads all marked buffers), C-e
  (create a file from the typed path in the filesystem float), C-d (cycle the search depth 1..6 in
  the filesystem floats and the standalone; delete in the buffer pickers), C-r (preview pane in the
  filesystem float), Esc/C-c/C-g (cancel), C-w (up a directory), dot (show hidden), RU layout
  without switching.
- Search depth: `g:LustyExplorerSearchDepth` is the starting value; C-d cycles it at runtime and the
  value survives navigation. The standalone restores its last query from
  `$XDG_STATE_HOME/lusty/history` (`LUSTY_HISTORY` overrides the path, `LUSTY_HISTORY=0` disables).
- glob-skip `~`/`*`/`?`, prefix anchor.
- Only dircolors/LS_COLORS; the path in the prompt is colored like zsh/oh-my-posh.
- Buffers: MRU order (current last) + fuzzy; grep: hits + `\b` boundaries.

## Phases

1. Crate skeleton + nix package (the `hypr-focus` pattern) + `--list <dir>` with listing
   (depth/skip/mount). Bench against Lua.
1. Port scoring + query filter + prefix anchor (unit tests from smoke).
1. LS_COLORS + ANSI output.
1. ratatui UI + keys + RU layout + gravity.
1. nvim shim: termopen + on_exit + options; wire up `,l`/`,C`/`,B`/`,G`; regression.
1. Buffers + grep modes.
1. Bench + documentation + Lua fallback.

## Nix packaging

- The code lives in a separate project: `~/src/lusty` (its own git repo; `default.nix` =
  `rustPlatform.buildRustPackage`, src `./.`, its own `Cargo.lock`, `meta.mainProgram = "lusty"`).
- /etc/nixos pulls it in as a flake input `lusty.url = "github:neg-serg/lusty"`; overlay
  `packages/overlays/tools.nix`: `callPkg (inputs.lusty.outPath) { }` → `pkgs.neg.lusty`.
- After changing the code in `~/src/lusty`: push it, then re-lock before rebuilding. The GitHub API
  is only reachable through the local proxy, otherwise `nix flake lock` times out and silently keeps
  the cached revision: `all_proxy=socks5h://127.0.0.1:10808 nix flake lock --update-input lusty`.

## Protocol hardening

- Escaping: backslash, TAB and LF inside a label, a path or a `D` name travel as `\\`, `\t`, `\n`,
  so a file name containing them cannot break the line framing. The client reverses this (`unescape`
  in `native.lua`); display labels keep TAB/LF in the visible escaped form because a raw LF makes
  `nvim_buf_set_lines` fail and a raw TAB breaks the grid pitch.
- Non-UTF8 names: `Entry` keeps the raw Unix path bytes (`rel_bytes`) and the serve rows send the
  path as those bytes; the label is the lossy form (display only). Opening, stat, preview and the
  long view all go through `Entry::path`, so such names stay usable.
- Backend death: `native.lua` reports `lusty serve`'s stderr/exit code with `vim.notify` and closes
  the float instead of leaving the loading placeholder forever.
- Long-view timestamps are local time (`localtime_r`, UTC only as a fallback), matching `eza -l`.
- Frecency: `native.lua` ships the open-frequency journal once as fire-and-forget
  `F <score> <escaped path>` records (no reply, so the response FIFO is untouched). With a non-empty
  map the empty query orders by (depth, score, canonical index) — the shallower depth still wins,
  and inside a depth the most frequent/recent paths lead. `LUSTY_FRECENCY=0` /
  `g:LustyExplorerFrecency=0` disables it (then no `F` is sent and the canonical order stands).
- Preview: `native.lua` opens a second float to the right (`C-r`) and asks for the pane with
  `V <index> <w> <h>`; the backend renders content / git diff / man / chafa and answers
  `V <lines> <dim>` plus one `L <text>` row per line (the `L ` prefix keeps a content line equal to
  `E` from ending the response). ANSI is stripped server-side and rows are clipped to the pane
  width, so the buffer never sees control bytes. The server announces `X preview` right after the
  banner; without that capability the key notifies instead of sending `V` (an old backend cannot
  reply, which would stall the response FIFO).
- Regression coverage: `cargo test` (`tests/serve_escape.rs`, `tests/serve_frec.rs`,
  `tests/serve_preview.rs`, `listing::tests`, `rank::tests`, `preview::tests`) and the headless
  `filesystem_float_special_smoke.lua` / `filesystem_float_frecency_smoke.lua` /
  `filesystem_float_preview_smoke.lua` in `check-lusty-smoke.sh` (each self-skips on an older
  deployed backend).
