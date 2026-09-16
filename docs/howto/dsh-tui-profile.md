# dsh tui profile — what it runs

The `tui` profile (`~/.dsh/profiles/tui`, launched as `dsh --profile tui`) is the daily terminal UI.
It runs **dsh-TUI** (`@deepseek-harness-tui/dsh-tui`, upstream
[ccch1mneyyy/dsh-TUI](https://github.com/ccch1mneyyy/dsh-TUI)) — a Cordis plugin that mounts its
front door over the same harness every other profile uses.

| Piece                    | Path                                                             |
| ------------------------ | ---------------------------------------------------------------- |
| Module (caretaker)       | `modules/user/nix-maid/apps/dsh-tui.nix`                         |
| Profile caretaker script | `modules/user/nix-maid/apps/dsh-tui-ensure.sh`                   |
| Profile-layer rewriter   | `modules/user/nix-maid/apps/dsh-tui-preset-patch.py`             |
| Plugin roster            | `modules/user/nix-maid/apps/dsh-terminal-plugins.nix`            |
| Profile                  | `~/.dsh/profiles/tui`                                            |
| TUI state                | `~/.dsh-tui/` (themes, `theme.json`, `lang.json`, history, pins) |
| Neg theme                | `modules/user/nix-maid/apps/dsh-tui-assets/themes/neg.json`      |
| Launcher                 | the `dsh` wrapper in `modules/user/nix-maid/apps/dsh.nix`        |

## What the caretaker does

`dsh-tui-ensure.sh` runs from the `dshTuiEnsure` activation script (every rebuild) and from the
`dsh-tui-ensure` user service (every login), so a rebuild after a manual `dsh plugin add` heals the
profile:

1. Removes a leftover `node_modules/@deepseek-ai` store link (see below).
1. Installs/upgrades `@deepseek-harness-tui/dsh-tui` — the floor is `0.10.1`; a newer version
   installed by hand is left alone.
1. Keeps `dsh-free-search` on the 0.1.5 settings API (`FS_WANT`).
1. Rewrites `cordis.patch.yml` through `dsh-tui-preset-patch.py`: the fallback preset row, the
   plugin roster, the free-search rows.
1. Seeds the repo-local plugins the neg preset mounts (`dsh-advisor`, `dsh-category-skill-reminder`,
   `dsh-ttsr`, plus the roster seeds).
1. Copies the neg theme and seeds `theme.json` / `lang.json` while unset.

## Facts that cost a boot each

- **No `@deepseek-ai` store link.** Older profiles on this host linked `node_modules/@deepseek-ai`
  to the harness tree, because a plugin pulled in its own peer copies and those broke the preset
  mount. dsh-TUI does not need it, and with the link present `dsh-app-boot`'s profile module
  fallback dies with `EROFS` — it creates its links under `node_modules/@deepseek-ai`, which through
  a store symlink is read-only. The caretaker deletes the link; dsh owns the fallback tree.
- **The preset row id is scoped.** dsh-TUI's bundle patch replaces the base `agent-presets` row with
  `dsh-tui-agent-presets`. A profile row targeting `agent-presets` is reported as
  `patch: entry "agent-presets" not found` on every start.
- **No second code-runtime row.** The dsh-TUI bundle already inserts `dsh-tui-code-runtime`. Adding
  a `code-runtime` insert alongside it registers `codeRuntime` twice and the boot dies at the
  loader, so the rewriter retires that block (and consumes a leftover one).
- **Language.** dsh-TUI ships `zh` and `en` only. Resolution order is `DSH_TUI_LANG` → the bundle's
  `lang` config → the persisted `~/.dsh-tui/lang.json` → the OS locale → `zh`. The caretaker seeds
  `en` once; `/lang` changes it and the choice survives a rebuild.
- **Theme format.** dsh-TUI themes are `~/.dsh-tui/themes/<name>.json` with `base`
  (`light`/`dark`/`dark-ansi`) plus a `colors` map of Theme keys, and the persisted choice lives in
  `~/.dsh-tui/theme.json`. `neg.json` uses that schema and the palette the rest of the system uses
  (kitty `theme.conf`, `neg.omp.json`).

## Verify

```bash
# composition only (no UI): no patch errors on stderr
dsh --profile tui --dump-config > /tmp/tui.yml   # stderr must be empty
rg -n "^- id: dsh-tui$|^- id: dsh-tui-agent-presets$" /tmp/tui.yml

# boot through a pty and look at the banner
timeout 30 script -qec 'stty rows 40 cols 120; dsh --profile tui' /tmp/tui.log
```

Manual install of a newer release (the caretaker keeps it if it is ≥ the floor):

```bash
cd ~/.dsh/profiles/tui && dsh plugin --profile tui add @deepseek-harness-tui/dsh-tui@latest
```
