# Lusty: roadmap (rendering, hotkeys, preview)

Agreed development plan for the pickers (standalone `lusty` + nvim float
`native.lua`/`native_pick`).

## Hotkeys

- Navigation: C-n/C-j/↓ down, C-p/C-k/↑ up, C-f/C-b/←/→ columns, PgUp/PgDn page, Home/End and C-a
  first (C-e is last in standalone only; it creates a file in the float).
- Query: C-u clear, C-h/BS backspace, C-w clear (files: then up).
- Actions: Enter/Tab open, C-t tab, C-o/C-v splits, C-e create file from the typed path (fs float),
  C-d delete buffer (buffers; with C-Space marks: the whole marked set) / cycle the search depth
  1..6 (filesystem floats and the standalone), C-r preview pane (filesystem float; C-Space previews
  in standalone), C-y sort order (we do not bind C-s: XOFF/kitty conflict), C-l cycle display mode,
  C-Space mark (multi-select in the native pickers: files — Enter opens all, buffers — C-d unloads
  all), Esc/C-c/C-g close.
- Standalone: the last query is restored from $XDG_STATE_HOME/lusty/history (LUSTY_HISTORY overrides
  the file, 0 disables it).
- Constraints: h/j/k/l are not touched (query letters); C-s is not bound in standalone (terminal
  suspend); shared keys keep standalone/float parity except the documented C-d/C-e/C-r/C-Space
  divergences.

## Display modes (eza approach)

- Source: metadata only for visible rows (serve: request M by index; standalone: `fs::metadata`
  lazily). The listing cache is mode-independent.
- grid — row-major (name+color).
- long — one line per file: perms uid size time name (like `eza -l`; the timestamp is local time),
  human-readable size. Standalone and nvim-float: C-l toggles; in float, metadata arrives via serve
  M requests only for the visible rows and is formatted by the same code as standalone
  (`listing::meta_line`).
- custom — choose a subset of the perm,user,size,time fields (name always last); config
  g:LustyExplorerColumns / LUSTY_COLUMNS / --columns.
- Sorting: name|ext|size|time — standalone (CLI --sort) and float (C-y cycles; serve re-sorts the
  listing and between changes returns to the canonical depth+name order).
  --reverse/--group-dirs-first — standalone (CLI) and float (g:LustyExplorerDirsFirst /
  g:LustyExplorerReverse or env LUSTY_DIRS_FIRST / LUSTY_REVERSE; as in standalone, they only affect
  the canonical name order).
- Icons (nerd font) optionally: standalone — LUSTY_ICONS=1; float — g:LustyExplorerIcons=1 (or
  LUSTY_ICONS=1); tree view later.
- Option priority: CLI > env LUSTY\_\* > g:LustyExplorer\*.
- Note: the long format is shared between standalone and serve (`listing::meta_line`, mask 1 perm /
  2 user / 4 size / 8 time) — the format is not duplicated.

## Preview (right-hand panel)

- Done in standalone (C-Space/Shift+P; width LUSTY_PREVIEW_WIDTH, limit LUSTY_PREVIEW_MAX_BYTES):
  images (chafa ANSI-art — works in any terminal; native kitty protocol — next step), git-diff of
  the selected file (unstaged), man pages (.1..9/.man/.gz via `man -l`).
- Not doing: file text/binary/dir/buffer/grep/stat/recent (item D).
- Async rendering / cancelling stale previews — not doing (render on selection change with cache).

## Work order

- A: hotkeys, standalone/float parity — done.
- B: long mode + sorting — done: standalone (CLI) and float (C-l long + serve M; C-y cycles
  name/ext/size/time).
- C: custom columns + env/config + icons — done (--columns/LUSTY_COLUMNS in standalone and float;
  g:LustyExplorerColumns is read by float; icons in float — g:LustyExplorerIcons=1 / LUSTY_ICONS=1).
- D: preview of text/dir/buffer/grep — by agreement, not doing.
- E: images, git-diff, man — done in standalone (chafa/git diff/man; C-Space/Shift+P); kitty
  protocol for images — next step.
- F: tests — serve M is covered by a Rust integration test (tests/serve_m.rs); serve escaping and
  non-UTF8 paths by tests/serve_escape.rs; frecency ordering by tests/serve_frec.rs; the V preview
  framing by tests/serve_preview.rs; headless float smokes: smoke.lua, native_float_smoke.lua,
  filesystem_float_smoke.lua, filesystem_float_icons_smoke.lua, filesystem_float_special_smoke.lua,
  filesystem_float_frecency_smoke.lua, filesystem_float_preview_smoke.lua (check-lusty-smoke.sh).
- G: frecency ordering — done: the client ships its open-frequency journal as `F` records and the
  empty query leads with the higher-scored paths inside each depth (opt-out: LUSTY_FRECENCY=0 /
  g:LustyExplorerFrecency=0).
- H: preview in the nvim float — done: C-r opens a sibling float and `V <index> <w> <h>` returns the
  pane (content / git diff / man / chafa); the backend advertises `X preview` so an older server
  makes the key a no-op. SGR runs become extmarks, so chafa art is coloured in the float. The
  standalone pane renders on a worker thread (no UI stalls) and places images with the kitty
  graphics protocol when the terminal supports it (LUSTY_KITTY=0 disables, ANSI art is the
  fallback).
- I: shared tables + parity — done: lusty/ru2en.lua and lusty/icons.lua are the single Lua sources
  (required by native.lua / native_pick.lua) and tests/tables_parity_smoke.lua compares them with
  `lusty --ru-map` / `--icon-map`, so the Rust and Lua tables cannot drift.
  tests/theme_parity_smoke.lua does the same for the theme reader (`--theme-map`; both sides honour
  LUSTY_THEME, and the Rust parser learned `selection.underline` / `match.fg`, which it used to
  ignore), and tests/ls_colors_parity_smoke.lua compares LS_COLORS resolution (`--color-map`)
  against ls_colors.code_for for one controlled palette.
- J: consolidation — done: the Lua port (explorer.lua, filesystem_explorer.lua, buffer_explorer.lua,
  buffer_grep.lua and its smoke) was removed; native\_\* is the only implementation, the regex
  translator moved to grep_pattern.lua and util.lua kept only basename/longest_common_prefix. No
  user-facing option was lost: `g:LustyExplorerFollowMountPoints` and
  `g:LustyExplorerAlwaysShowDotFiles` are wired again through `serve --follow-mounts` / `--dots`
  (covered by filesystem_float_dots_smoke.lua).
