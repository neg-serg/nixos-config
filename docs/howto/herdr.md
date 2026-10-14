# Herdr — runtime for the dsh agent workflow

Herdr ([herdr.dev](https://herdr.dev), nixpkgs `herdr`) is a terminal workspace manager built for
coding agents: workspaces/tabs/panes, a sidebar that rolls agent state up, git-worktree checkouts as
grouped workspaces, and a background server so sessions survive closing the terminal.

On trantor it is the runtime for the parallel-agent workflow: `dsh --profile tui` sessions live in
Herdr panes, `dsh-worktree` opens new trees as Herdr workspaces, and the `dsh-herdr` plugin reports
the session state (working/idle/blocked) so a dsh pane is a first-class agent in the sidebar,
notifications and `herdr agent wait`.

## Enabling

`features.dev.ai.herdr.enable = true` (set on trantor in `hosts/trantor/default.nix`) installs
`pkgs.herdr` and deploys `files/herdr/config.toml` as a live link at `~/.config/herdr/config.toml` —
see `modules/user/nix-maid/apps/herdr.nix`.

Config edits apply without a rebuild:

```sh
herdr config check          # validate ~/.config/herdr/config.toml
herdr server reload-config  # push the change into the running server
```

## Using

```sh
herdr                 # launch or attach to the default session
herdr --session work  # a separate named session (own panes, sockets, state)
herdr status server   # is the background server up?
herdr                 # run again after closing the terminal -> reattach
```

- `ctrl+b` enters prefix mode (the same prefix as zellij); `prefix+?` shows every binding,
  `prefix+q` detaches. `prefix+h/j/k/l` and `alt+h/j/k/l` focus panes.
- One workspace per project: `prefix+shift+n` creates one, `prefix+c` a tab, `prefix+v` /
  `prefix+minus` split.
- Herdr is mouse-native: click rows/tabs/panes, drag borders, right-click menus.
- Panes and agents keep running after the client detaches; `herdr server stop` stops the session and
  its panes.

## dsh in Herdr

dsh is not one of the agents Herdr recognizes by reading the screen, so a pane without the plugin is
a plain terminal. The `dsh-herdr` plugin (`modules/user/nix-maid/apps/dsh-herdr`, mounted by the tui
profile roster) uses Herdr's self-report protocol
([Add Herdr support to your agent](https://herdr.dev/docs/add-herdr-support/)): while `HERDR_ENV=1`
it maps `agent/status` running/idle to working/idle, and the `approval/request` and
`user-questions/request` waterfalls to blocked after a grace period — a request that auto-settles
stays silent, and answering the card returns the pane to working. Reports are fire-and-forget:
outside a Herdr pane the plugin is inert, and `DSH_HERDR=0` disables it.

Check what Herdr sees, and drive it from scripts or another agent:

```sh
herdr agent list
herdr pane get "$HERDR_PANE_ID"
herdr agent wait dsh --until blocked --timeout 120000
```

Limitation: nixpkgs ships Herdr 0.9.1, which forwards state but has no resume-command support, so a
server restart brings the pane back as a shell rather than as the resumed dsh session. Resume
commands need Herdr >= 0.9.2; the plugin already reports the session id, so enabling that later is a
version bump, not a plugin change.

## dsh-worktree: `--open herdr`

`dsh-worktree new <name>` creates the tree and opens it. Inside a Herdr pane `--open auto` now picks
herdr, which runs:

```sh
herdr worktree open --cwd <repo> --path <tree> --label wt:<name> --focus
herdr pane run <root-pane> "dsh --profile tui"
```

The tree becomes a workspace **grouped under the repository** (Git provenance in the sidebar).
`--open herdr` forces the mode, `HERDR_BIN_PATH` selects the binary (a Herdr pane sets it). The
other modes (`kitty`, `zellij`, `print`) are unchanged; `auto` order is herdr -> kitty -> zellij ->
print. Details: [dsh-worktrees.md](./dsh-worktrees.md).

## Config

`files/herdr/config.toml` (deployed as a live link):

- theme: catppuccin base plus neg palette tokens (the colours zellij's `neg-dark` uses);
  `onboarding = false`.
- keys: `ctrl+b` prefix and `alt+h/j/k/l` pane focus next to the prefix binds. No Cyrillic
  duplicates: the ru-layout daemon pins terminal windows to `us`
  ([hotkeys-ru-layout.md](./hotkeys-ru-layout.md)).
- Herdr's own `worktrees.directory` stays at its default; dsh-worktree trees live under
  `~/.dsh/worktrees` and are *opened* by Herdr rather than created by it.

## Package notes

- Version: nixpkgs' `herdr` (0.9.1 at the current pin; upstream is newer). Updates ride nixpkgs
  bumps.
- The package builds from source (Rust plus zig/ghostty dependencies). With
  `--option substitute false` the zig-deps fixed-output derivation fetches from
  `deps.files.ghostty.org` inside the sandbox; if that fails with `NetworkUnreachable`, fetch the
  hash-verified FOD explicitly (`nix-store -r <herdr-zig-deps.drv>`) and rebuild — nothing is built
  by hand.
- License: AGPL-3.0-or-later.

## Verification

```sh
herdr --version
herdr config check
herdr status server
node modules/user/nix-maid/apps/dsh-herdr/test.mjs   # plugin contract
bash scripts/dev/check-dsh-worktree.sh               # --open herdr gates
```
