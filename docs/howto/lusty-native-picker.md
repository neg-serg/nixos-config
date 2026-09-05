# Lusty-native: separate Rust picker (architecture)

## Goal

Replace the slow parts of LustyExplorer (the Lua port in nvim) with a separate native process while
keeping nvim as the editor. The target win is 10× or more on typing and on listing large directories.

Measurements (headless, repo copy, /etc/nixos):

| Operation                                  | Now (Lua)              | Target (Rust)                      |
| ------------------------------------------ | ---------------------- | ---------------------------------- |
| list /home/neg, depth 1 (11 entries)       | 4.9 ms                 | < 1 ms                             |
| list /etc/nixos, depth 2 (271 entries)     | 8.0 ms                 | < 2 ms                             |
| list /nix/store, depth 1 (151,363 entries) | **4884 ms**            | < 150 ms                           |
| fuzzy.score × 5000                         | 1.2 ms                 | < 0.5 ms                           |
| typing (latency)                           | nvim float redraw      | native ratatui, partial redraw     |

Two bottlenecks in the current Lua port:

1. **B1 — nvim float-window redraw** on every keypress (this is the "typing lags" on ordinary
   directories; the logic here is 0.1–0.2 ms per callback).
1. **B2 — synchronous listing** `vim.fn.readdir` + one `vim.fn.getftype` (stat) per file on the
   UI thread: 151k files = 4.9 s. Native `fd` does the same 151k in ~107 ms and asynchronously.

## Process model (Model 1, fzf-style)

- An nvim wrapper (`,l`/`,C`/`,B`/`,G`) opens a terminal via `termopen` and runs
  `lusty-native <mode> <root>`.
- The binary draws on the alternate screen (ratatui/crossterm); the user types/picks; on selection
  the binary prints an `ACTION<TAB>PATH` line to stdout and exits with code 0; cancel — code 1.
- `on_exit` in Lua reads stdout and opens the file in nvim (edit/tab/split), reusing the current
  buffer-opening logic. No RPC daemon is needed.
- Later, optionally: a persistent process + msgpack-RPC via `nvim --listen`.

## Components

1. `~/src/lusty-native` (flake input `lusty-native` in /etc/nixos) — a Rust crate (binary
   `lusty-native`):

   - `cli`: mode (files|buffers|grep), root, depth, skip-dirs, follow-mounts, dotfile flag,
     initial query.
   - `listing`: `ignore`/`walkdir` + `rayon` (parallel traversal), depth limit, skipping mount
     points (/proc/self/mountinfo), skip-dirs glob (`~`/`*`/`?`), "less nested on top" ordering.
   - `scoring`: port of `fuzzy.lua` (fzy-style) to Rust + prefix anchor on the first letter (the
     first letter of the query must be a name prefix). Mercury — optional.
   - `colors`: LS_COLORS parsing (env → dircolors file → `dircolors -b`), ANSI coloring of
     dir/symlink/ext; the same priority as in the current `ls_colors.lua`.
   - `ui`: ratatui — query line, list with incremental partial redraw, gravity (bottom by default),
     selection, RU layout (dual-mapping of physical keys to EN), the same key set.
   - `output`: on Enter/Tab/C-t/C-o/C-v prints `ACTION<TAB>PATH`.

1. `files/nvim/lua/lusty/native.lua` — a shim: `termopen` + `on_exit` + option forwarding. The
   old Lua port stays as the fallback (`g:LustyExplorerNative=0`).

## UX parity (must be preserved)

- Keys: Enter/Tab, C-t, C-o/C-v, C-n/C-p, C-f/C-b (columns), C-l (long mode with metadata), C-y
  (sort name/ext/size/time), C-u (clear), Esc/C-c/C-g (cancel), C-w (up a directory), dot (show
  hidden), RU layout without switching.
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

- The code lives in a separate project: `~/src/lusty-native` (its own git repo; `default.nix` =
  `rustPlatform.buildRustPackage`, src `./.`, its own `Cargo.lock`,
  `meta.mainProgram = "lusty-native"`).
- /etc/nixos pulls it in as a flake input `lusty-native.url = "path:/home/neg/src/lusty-native"`;
  overlay `packages/overlays/tools.nix`: `callPkg (inputs.lusty-native.outPath) { }` →
  `pkgs.neg.lusty-native`.
- After changing the code in `~/src/lusty-native`: run `nix flake lock --update-input lusty-native`
  before rebuilding.
