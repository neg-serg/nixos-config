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

- `ctrl+s` enters prefix mode (the key zellij uses for its session mode); `prefix+?` shows every
  binding, `prefix+q` detaches. `prefix+h/j/k/l` and `alt+h/j/k/l` focus panes.
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
stays silent, and answering the card returns the pane to working. On Herdr >= 0.9.2 every report
also carries the resume command (`dsh --profile tui --resume <id>`); older servers reject that
trailing argv, so the plugin probes `herdr --version` once and attaches it only when supported.
Reports are fire-and-forget: outside a Herdr pane the plugin is inert, and `DSH_HERDR=0` disables
it.

Check what Herdr sees, and drive it from scripts or another agent:

```sh
herdr agent list                                   # every agent, with state
herdr pane get "$HERDR_PANE_ID"                    # this pane's agent row
herdr agent wait wD:p1 --until blocked --timeout 120000
```

A bare `dsh` is the agent *kind* label, not a usable target (`herdr agent wait dsh` answers
`agent_not_found`): address an agent by its pane id, or give it a stable name once with
`herdr agent rename wD:p1 main` and use that name afterwards.

Native session restore (Herdr >= 0.9.2) is on by default: after a server restart Herdr reopens each
pane in its directory and runs the reported `dsh --profile tui --resume <id>`, so the pane comes
back as the same conversation. Turn it off with `[session] resume_agents_on_restore = false` in
`~/.config/herdr/config.toml`; the plugin keeps reporting state either way.

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
- keys: `ctrl+s` prefix and `alt+h/j/k/l` pane focus next to the prefix binds. Herdr consumes the
  prefix, so zsh's `^S` history-incremental-search-forward does not fire inside a Herdr pane; no
  Cyrillic duplicates are needed because the ru-layout daemon pins terminal windows to `us`
  ([hotkeys-ru-layout.md](./hotkeys-ru-layout.md)). Kitty's hint layer sits on `Ctrl+Alt+S`, not
  `Ctrl+S`, so the prefix reaches Herdr unmangled inside a kitty pane.
- agent navigation: `prefix+u` / `prefix+i` move to the previous/next agent row, `prefix+alt+1..9`
  jumps to the nth one; the Goto picker (`prefix+g`) filters with `b`/`w`/`i`/`d` for
  blocked/working/idle/done. `prefix+shift+r` reloads the config (including local keybindings) from
  inside Herdr.
- sidebar: agent rows keep the location line, then show `terminal_title_stripped` — for dsh that is
  the statusline title (branch, dirty counts, tokens, turn) — and the agent label. The per-agent
  `rows_by_agent` table only accepts built-in agent ids, not a self-reported label such as `dsh`.
- Herdr's own `worktrees.directory` stays at its default; dsh-worktree trees live under
  `~/.dsh/worktrees` and are *opened* by Herdr rather than created by it.

## Package notes

- Version: nixpkgs' `herdr` (0.9.3 at the pinned nixos-unstable channel release of 2026-10-14;
  upstream may be newer). Updates ride the `nixpkgs` pin in `flake.nix`.
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
