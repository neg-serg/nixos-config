# dsh martty profile — the upstream terminal UI, side by side with Tianshu

Martty is the upstream DeepSeek Harness TUI, renamed from
`@openma/deepseek-harness-tui` (npm `martty`, Rust/ratatui painter, built on the
same Cordis plugin model). This host runs it as a **second dsh profile** so the
trial cannot disturb the daily Tianshu TUI in the `tui` profile.

## What is installed and where

| Piece | Path |
| --- | --- |
| Module (caretaker + activation) | `modules/user/nix-maid/apps/dsh-martty.nix` |
| Profile caretaker script | `modules/user/nix-maid/apps/dsh-martty-ensure.sh` |
| Plugin roster, shared with the tui profile | `modules/user/nix-maid/apps/dsh-terminal-plugins.nix` |
| Profile | `~/.dsh/profiles/martty` |
| Launcher | `dsh-martty` (`modules/user/nix-maid/apps/dsh.nix`), i.e. `dsh --profile martty` |
| Martty state | `~/.martty` |

The caretaker runs on every rebuild and on every login (same pattern as the tui
profile) and does four things: installs/upgrades `martty` in the profile,
installs `dsh-free-search`, links the profile's `@deepseek-ai` to the harness
tree, and writes the loader rows plus the repo-local plugin copies. It creates
the profile on first run, so no manual `dsh plugin add` is needed.

## Differences from the tui profile

- **No Russian patch and no Tianshu theme.** Martty's interface is English in the
  bundle (no Chinese UI literals), so `dsh-tui-ru-assets/` and its patcher do not
  apply; `~/.dsh-tui/` is unused by this profile.
- **The same host/agent plugins.** Both terminal profiles mount the roster in
  `dsh-terminal-plugins.nix`, so the agent inside Martty behaves like the one in
  Tianshu (`/mode`, `/fast`, `/worktree`, `/diff`, presets, memory, …).
  The OSC-based plugins (`dsh-statusline`, `dsh-notify-input`) are mounted but
  silent there: they guard on `process.stdout.isTTY`, and in the Martty profile
  the TTY belongs to the client process while the host's stdout is the ACP pipe.
- **No self-update hook.** Martty ships the native binary inside the npm tarball
  (static-PIE ELF for `linux-x64`, no patchelf on NixOS) and the caretaker pins
  the floor in `dsh-martty-ensure.sh` (`MARTTY_WANT`).

## Commands

```sh
dsh-martty                 # launch the trial profile
dsh --profile martty       # same thing
dsh plugin --profile martty list
```

Re-apply the profile layer by hand (the activation/login services do this too):

```sh
/nix/store/...-dsh-martty-ensure   # or: systemctl --user start dsh-martty-ensure
```

## Notes and pitfalls

- **Id-targeted rows, never `insert`, for bundled plugins.** `dsh plugin add`
  registers a plugin in `dsh.profile.bundles`, whose own patch layer already
  inserts its row. Adding an `insert` for the same id in the profile layer is
  `duplicate loader entry id: <id>` and the whole plugin tree fails to load — the
  `tui` profile was down on exactly that (found 2026-09-16 while setting this up)
  and both profiles share the fixed `searchRows`.
- The tui profile relinks `@deepseek-ai` to the harness tree and excludes the
  harness `standard` preset; the martty profile gets the same treatment because
  the seeded plugins import harness packages (`@deepseek-ai/dsh-llm`,
  `@deepseek-ai/dsh-tools`).
- A run from an interactive shell shows a `dsh>` prompt instead of finishing: the
  CLI drops into its REPL when stdin is a TTY. The systemd/activation context
  redirects stdin, which is why the services are oneshots.

## Removal

Delete `dsh-martty.nix` and `dsh-martty-ensure.sh`, drop the `dshMartty` entry
and launcher from `dsh.nix`, remove `roster` usage if the tui profile no longer
shares it, then:

```sh
rm -rf ~/.dsh/profiles/martty ~/.martty
```
