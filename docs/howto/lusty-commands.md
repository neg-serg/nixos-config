# Lusty pickers: commands, options and behaviour

The pickers are rendered by the native Rust backend (`lusty serve`) as Neovim floating windows,
wired up from `files/nvim/init.lua` on the `VeryLazy` event (`require'lusty'`). The historical Lua
port (`explorer.lua`, `filesystem_explorer.lua`, `buffer_explorer.lua`, `buffer_grep.lua`) was
removed with the consolidation, so there is no fallback mode any more: if the `lusty` binary is
missing, the pickers notify instead of opening.

Architecture and the wire protocol: [lusty-picker.md](./lusty-picker.md). Plan, status and the work
order: [lusty-roadmap.md](./lusty-roadmap.md).

## Commands and keys

| Command                          | Key       | Action                                                |
| -------------------------------- | --------- | ----------------------------------------------------- |
| :LustyFilesystemExplorer [path]  | <Leader>C | filesystem float (cwd, or the given path)             |
| :LustyFilesystemExplorerFromHere | <Leader>l | filesystem float from the current file's dir (nowait) |
| :LustyBufferExplorer             | <C-b>     | MRU buffer float                                      |
| :LustyBufferGrep                 | <C-g>     | Ruby-ish regex over the loaded buffers                |
| :LustyRecent                     | <Leader>. | recent files or visited directories                   |

`g:LustyExplorerDefaultMappings = 0` disables the mappings. The old non-prefixed names
(`:BufferExplorer`, `:FilesystemExplorer`, `:FilesystemExplorerFromHere`) remain as warning stubs
like in the original plugin. `<Leader>l` fires instantly (nowait) so the first query letter is not
swallowed by the old `,l[fbgr]` chords — those functions moved to `,C` / `C-b` / `C-g` / `,.`.

Inside the floats (the full list is in [lusty-roadmap.md](./lusty-roadmap.md#hotkeys)):

- Query: letters/`/`/dot type; `C-u` clear, `C-h`/`BS` backspace, `C-w` clear then up a directory.
- Navigation: `C-n`/`C-j`/`↓`, `C-p`/`C-k`/`↑`, `C-f`/`C-b`/`←`/`→`, PgUp/PgDn, Home/`C-a`, End.
- Actions: Enter/Tab open, `C-t` tab, `C-o`/`C-v` splits, `C-d` depth cycle (fs) or delete
  (buffers), `C-l` long view, `C-y` sort cycle, `C-Space` mark, `C-e` create file (fs), `C-r`
  preview (fs), Esc/`C-c`/`C-g` close.

## Behaviour

- Floats: bottom-anchored rounded windows (gravity `bottom`), sized from `g:LustyExplorerWidthRatio`
  / `g:LustyExplorerMaxHeightRatio` (`LUSTY_WIDTH` / `LUSTY_ROWS` win).
- Fuzzy ranking: fzy-style with the first query letter anchored to the basename start; the Russian
  (JCUKEN) layout is mapped to EN keys automatically (`ru2en.lua`).
- Filesystem float: depth-limited parallel walk, skip dirs (`g:LustyExplorerSkipDirs`), mount points
  crossed only with `g:LustyExplorerFollowMountPoints`, dotfiles from the query or
  `g:LustyExplorerAlwaysShowDotFiles`, LS_COLORS cell colours, frecency ordering for the empty
  query, sort cycle (`C-y`), long view (`C-l`), icons, multi-select (`C-Space`), create-file
  (`C-e`), runtime depth (`C-d`), preview pane (`C-r`, file content / git diff / man / chafa).
- Buffer float: MRU order with the current buffer last, `C-d` unloads the selection (or the whole
  marked set).
- Grep float: the Ruby-ish pattern is translated to a Vim magic pattern (`grep_pattern.lua`) and is
  always case-insensitive; hits carry file/line/context/match highlights and open at the line.
- Recent float: `v:oldfiles` merged with the frecency journal, optionally switched to recorded
  directories with `C-r`.

## Options

`g:LustyExplorer*` options, with the `LUSTY_*` environment variable that wins over the `g:` one
where both exist:

| Option                            | Default         | Env                     |
| --------------------------------- | --------------- | ----------------------- |
| `LustyExplorerDefaultMappings`    | on              | –                       |
| `LustyExplorerSearchDepth`        | 2 (start value) | –                       |
| `LustyExplorerSkipDirs`           | `pic,tmp`       | –                       |
| `LustyExplorerFollowMountPoints`  | off             | –                       |
| `LustyExplorerAlwaysShowDotFiles` | off             | –                       |
| `LustyExplorerIcons`              | off             | `LUSTY_ICONS`           |
| `LustyExplorerDirsFirst`          | off             | `LUSTY_DIRS_FIRST`      |
| `LustyExplorerReverse`            | off             | `LUSTY_REVERSE`         |
| `LustyExplorerColumns`            | all fields      | `LUSTY_COLUMNS`         |
| `LustyExplorerFrecency`           | on              | `LUSTY_FRECENCY`        |
| `LustyExplorerFuzzyEngine`        | `smart`         | –                       |
| `LustyExplorerInputDebounce`      | 20 ms           | –                       |
| `LustyExplorerWidthRatio`         | 0.8             | `LUSTY_WIDTH` (columns) |
| `LustyExplorerMaxHeightRatio`     | 0.4             | `LUSTY_ROWS` (rows)     |
| `LustyExplorerPreviewWidth`       | `box/3`         | `LUSTY_PREVIEW_WIDTH`   |
| `LustyExplorerSelStyle`           | 1 (theme file)  | –                       |

`g:LustyExplorerNative` used to select the removed Lua port; setting it to `0` now warns and uses
the native picker anyway.

## Verification

`scripts/dev/check-lusty-smoke.sh` (run by `just lint`) executes the headless suites: the native
float smokes plus the shared-helper and parity checks (`tables_parity`, `theme_parity`,
`ls_colors_parity`). The parity suites self-skip on a deployed backend that predates the `--ru-map`
/ `--icon-map` / `--theme-map` / `--color-map` dump flags.
