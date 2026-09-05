# LustyExplorer: Lua port for modern Neovim

Port of the classic plugin [sjbach/lusty](https://github.com/sjbach/lusty) (LustyExplorer, VimL +
Ruby) to Lua for the `files/nvim` config. The original did not work in Neovim — it has no `if_ruby` interface.

The code lives in `files/nvim/lua/lusty/` and is wired up from `files/nvim/init.lua` on the `VeryLazy` event
(`require'lusty'`).

## Commands and keys

| Command                         | Key       | Action                                                             |
| ------------------------------- | --------- | ------------------------------------------------------------------ |
| :LustyFilesystemExplorer [path] | <Leader>C | filesystem explorer (cwd, or the given path)                       |
| :LustyFilesystemExplorerFromHere | <Leader>l | filesystem explorer from the current file's directory (nowait, instant) |
| :LustyBufferExplorer            | <Leader>B | buffer explorer (MRU + fuzzy)                                      |
| :LustyBufferGrep                | <Leader>G | regex search across all loaded buffers                             |

> Note: ,l used to be the prefix of the old ,lf/,lr/,lb/,lg chords — nvim waited for a second key and
> swallowed the first letter typed (,lgames opened BufferGrep with 'ames'). Now ,l is instant (nowait)
> and the other functions live on ,C / ,B / ,G. The old chords can be restored in
> files/nvim/lua/lusty/init.lua if the quick ,l is not needed.

The old names `:BufferExplorer`, `:FilesystemExplorer`, `:FilesystemExplorerFromHere` remain as
stubs with a warning (as in the original).

## Behavior

- The explorer opens in a **floating window** (rounded border, centered on screen) instead of a split —
  it does not touch the window layout and cannot collapse neighboring windows into microscopic strips.
  The last line of the window is a `>>` prompt.
- Typing filters the entries with modern fuzzy scoring (fzy-style: bonuses for word starts and for the
  separators `/`/`-`/`_`/`.`/camelCase, for contiguous runs, penalty for breaks). The original
  Mercury (ported 1:1) is available as `g:LustyExplorerFuzzyEngine = 'mercury'`.
- The first letter of the query must be a prefix of the file name (not of the whole path): `c` will
  not find `pic.jpg`, even though the name contains the substring `c` — so typing does not latch
  onto entries "by the middle of the name".
- Keyboard layout: dual-mapping in langmapper style — under the Russian JCUKEN layout, physical
  keys work as EN (the key that produces `yu` in the Russian layout types `.` and reveals hidden
  files; the key that produces `i` types `b`, etc.), so no layout switching is needed.
- `<Enter>`/`<Tab>` — open the selection; `<C-t>` — open in a new tab; `<C-o>`/`<C-v>` — open
  in a horizontal/vertical split.
- `<C-n>`/`<C-p>` — next/previous; `<C-f>`/`<C-b>` — move by columns; `<C-u>` — clear the
  prompt; `<Esc>`/`<C-c>`/`<C-g>` — cancel (just closes the window and returns focus, without
  switching buffers and without `E37` errors even with `'hidden' off`).
- Buffers are ordered by MRU (the current one last, highlighted); with an empty query it is plain MRU,
  with a query — first by Mercury score, ties broken by buffer number.
- Filesystem explorer: by default the search goes **2 levels deep** (`g:LustyExplorerSearchDepth`, 1 =
  the classic list of the current directory only) — files in subdirectories are shown with their path
  (`sub/gamma.txt`) and are found by fuzzy typing; **less nested entries always come first** (the
  current directory first, then level 2), so `Tab`/`Enter` does not jump straight into the depth; the
  deep search **does not enter mount points** (`music`, `/proc`, other filesystems) or **excluded
  directories** (by default `pic`, `tmp` — the `g:LustyExplorerSkipDirs` list) — they are visible
  but not traversed; `g:LustyExplorerFollowMountPoints = 1` enables traversing mounts,
  `g:LustyExplorerSkipDirs = ''` disables the exclusions. Directory memoization (`<C-r>` refreshes),
  navigation to `dir/` and `../`, `~` and `$VAR` in the prompt, dotfiles hidden until the query
  starts with `.` (or `g:LustyExplorerAlwaysShowDotFiles = 1`), masks from `&wildignore` (or the
  deprecated `g:LustyExplorerFileMasks`).
- Colors like `ls --color`: the palette comes **strictly from the `LS_COLORS` inherited from the
  shell** (here: `~/.config/dircolors/dircolors` → `dircolors -b` in zsh), with no custom rules of
  our own on top. If `LS_COLORS` is absent from the environment, the `dircolors -b` default is used
  (same as plain `ls --color`). Types `di`/`ln`/`ex`/`so`/`pi`..., then `*.ext` rules. The
  same applies to buffer names in BufferExplorer (by file extension).
- Float sizing: width ~90% of the screen, height adjusts to the content (the whole table + prompt
  line), capped at ~80% of the screen height; the minimum is one row per entry (when the count is
  small). Gravity defaults to `bottom` — the window sits at the bottom edge, like the original
  Lusty's table (configurable, see options). The bottom line is the `>>` prompt, without hints. In
  the filesystem explorer the path in the prompt is shown like a shell prompt: `$HOME` is shortened
  to `~`, and the tilde/separators/path text are colored with colors from `neg.omp.json`
  (`#287373`/`#005faf`/`#95a7bc`).
- `<C-d>` in the buffer explorer — unload the selected buffer.
- `<C-a>`/`<Shift-Enter>` in the filesystem explorer — open all files from the current view;
  `<C-e>` — create a new file from the prompt text.

## Options

- `g:LustyExplorerDefaultMappings` (default 1) — `0` disables the default keys.
- `g:LustyExplorerInputDebounce` (80 ms) — table rebuild delay while typing: letters echo
  instantly, the list updates after a pause (`0` — recompute on every keypress).
- `g:LustyExplorerAlwaysShowDotFiles` — always show dotfiles.
- `g:LustyExplorerFileMasks` — deprecated equivalent of `&wildignore`.
- `g:LustyExplorerShowColors` (enabled by default) — `0` disables dircolors coloring of cells.
- `g:LustyExplorerWidthRatio` (0.9) — fraction of the screen width taken by the float (0.4–1.0).
- `g:LustyExplorerMaxHeightRatio` (0.8) — maximum float height as a fraction of the screen (0.3–0.95).
- `g:LustyExplorerGravity` (`bottom`) — vertical float position: `top`, `center` or `bottom`.
- `g:LustyExplorerSearchDepth` (2) — how many levels down to search for files (`1` — the current
  directory only, up to 6).
- `g:LustyExplorerFollowMountPoints` (0) — `1` lets the deep search enter mount points.
- `g:LustyExplorerSkipDirs` (`pic,tmp`) — comma-separated directory names (or paths with
  `~`/`*`/`?`) that the deep search does not enter; `''` — disable.
- `g:LustyExplorerFuzzyEngine` (`smart`) — fuzzy ranking: `smart` (fzy-style, default) or
  `mercury` (the original Lusty algorithm).

## Config changes

- Removed `{ '<leader>l', ... }` (files in the current directory) from
  `files/nvim/lua/plugins/ui/snacks.lua` — the `gz` combo does the same thing, and the
  `<Leader>l` prefix is freed up for Lusty (`lf/lr/lb/lg`).

## Limitations

- LustyJuggler (the MRU-buffer bar) was not ported — it was not requested.
- BufferGrep translates Ruby-like regex into Vim patterns (plain 'magic'): supports `(a|b)`,
  `+`, `?`, `{m,n}`, `\b`, `\d`, `\w`, `\s`; the search is always case-insensitive.
  Complex constructs (lookaheads, etc.) are not supported.
- Files over `scp://` are shown (via `ssh ls`), but opening requires netrw, which is disabled in
  the config.

## Verification

Headless tests (nvim): `nvim --clean --headless -l files/nvim/lua/lusty/tests/smoke.lua` —
filesystem explorer open/filter/navigation/recursion, dircolors coloring, MRU buffer order, C-d,
BufferGrep hits (including `\b` boundaries).

Changes take effect after the config is rebuilt:
`nh os switch /etc/nixos#odin --option substitute false`.
