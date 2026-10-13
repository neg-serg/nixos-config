# iris — shell IntelliSense on trantor

[iris](https://github.com/versenilvis/iris) is the shell autocompletion wrapper around the
interactive zsh. `files/shell/zsh/iris.zsh` sources `iris init zsh` from `.zshrc`: the outer shell
execs `iris`, iris spawns the real zsh on a PTY, and the child-side ZLE/IPC hooks report the line,
cwd and aliases back. Config and theme are deployed from `files/iris/` (nix-maid symlinks them to
`~/.config/iris/`), the binary from `packages/iris/`.

## Local patches (`packages/iris/`)

The package is v0.7.3 plus `[trantor]` patches; the rationale for each lives next to the patch list
in `default.nix`. In short:

- `iris-select-fallthrough` — the accept key (Tab) inserts the highlighted suggestion while the menu
  is visible and falls through to zsh otherwise (fzf-on-tab, `~/m/new`).
- `iris-empty-keybindings` — `""` disables a keybinding instead of being replaced by the upstream
  default (`toggle-mode = ""` keeps `^R` for hishtory).
- `iris-menu-footer` — the footer lists only bound keys, including non-arrow navigation.
- `iris-command-prefix-noise` — a word that exactly names a program on PATH suppresses the
  prefix-only sibling menu, so `^P` reaches the shell's history search.
- `iris-nav-fallthrough` — navigation keys are consumed only while the overlay cursor can move; at
  the edge of the menu the key falls through to zsh (menu cleared first). This makes `ds` + `^P`
  recall the last `ds…` command instead of swallowing the key.
- `iris-spec-relevance` — top-level suggestions must be runnable: a registry spec is kept only when
  its binary is on PATH or the word is a shell builtin (`cd`, `exec`, `source`, …); macOS-only
  commands (`dscacheutil`, `dscl`, `defaults`, `launchctl`, `networksetup`, `pmset`, `pkgutil`,
  `simctl`, `codesign`, `xcode-*`, `xcodes`) are not registered off macOS. Subcommand completion for
  an already typed word is untouched. Go tests cover both rules; `doCheck` runs the upstream suite
  with the one mtime-flaky test skipped.

## Behaviour that matters

- `ghost-text = 0`: menu only, nothing is drawn after the cursor.
- `select = "tab"`: accepts while the menu is visible, otherwise the key stays zsh's.
- `^P` / `^N`: with the menu open they move the selection; at the list edge, or with the menu closed
  (`navigate-closed = "shell"`), they are forwarded to zsh, so `up-line-or-beginning-search` keeps
  working.
- `^R` belongs to hishtory (`toggle-mode` is disabled), arrows are not bound by iris at all.
- `mode = "spec"`: suggestions come from command specs, file generation and AI; shell history is not
  used as a ghost source.

## Smoke test

Run this in a **new** terminal: a running session keeps the binary it started with, and
`iris reload` re-execs the same binary rather than the newly deployed one.

1. `ds` + `^P` — the line becomes the last history entry starting with `ds` (for example
   `dsh --profile tui`) and the menu disappears.
1. `ds` alone — the menu lists only real commands (`dsh`, `dsh-statusline`, `dsh-url`,
   `dsh-worktree`); no `dscacheutil`/`dscl`.
1. `^N` moves the highlight down, `^P` moves it back up, `Tab` accepts the highlighted entry.
1. `nh` + `^P` and `dsh` + `^P` — history recall without a menu opening.
1. `cd ` — file/directory suggestions still work (multi-token path is not filtered).

## Isolated end-to-end check (agent recipe)

The interactive behaviour can be driven without touching the user's terminals: start a scratch kitty
with `allow_remote_control yes` and `listen_on unix:/tmp/…/sock`, point `IRIS_CONFIG_DIR` at a copy
of `files/iris/`, isolate `XDG_STATE_HOME` (zsh history) and `XDG_CACHE_HOME` (iris log), then send
keys with `kitten @ --to unix:SOCK send-text --match all 'ds'` / `send-key --match all ctrl+p` and
read the screen back with `get-text --match all --extent screen`. Keep the window on a headless
output or a hidden special workspace; `get-text` works while it is not visible.

## Disabling

iris is activated by the `source "${ZDOTDIR}/iris.zsh"` line at the top of `files/shell/zsh/.zshrc`.
Commenting it out and switching runs plain zsh again; the package and `~/.config/iris/` stay
deployed, so re-enabling is the same one-line change. Sessions that already run iris keep their
binary until they are closed.

## Rebuilding

```sh
nix build --impure --expr \
  '(builtins.getFlake "/etc/nixos").nixosConfigurations.trantor.pkgs.neg.iris' \
  --option substitute false -L
sudo nixos-rebuild switch --flake .#trantor --option substitute false < /dev/null
```
