# dsh web: forks instead of patches — current architecture

How dsh web GUI changes (profile `~/.dsh/profiles/web`) are arranged after the "patches → forks"
migration.

## Two mechanisms (there used to be five)

### 1. Own plugins — a fork repository (canonical source)

All plugins written for yourself live in the fork `~/src/1st-level/@projects/dsh-web-ui` (remotes
`fork` → `neg-serg/dsh-web-ui`, `upstream` → `zhu1090093659/dsh-web-ui`), under `packages/`:

| Package            | What it does                                                                                                                                                                                               |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `dsh-terminal-ui`  | the neg theme (navy glass, Iosevka, wide column)                                                                                                                                                            |
| `dsh-gui-tweaks`   | answers numbered in dialogs, bash-line wrapping, composer focus, todo_write → todo list, ask_user_question → question card, thoughts collapsed + code with a height cap, sidebar logo line hidden          |
| `dsh-prompt`       | terminal placeholder `❯_` in the composer                                                                                                                                                                 |
| `dsh-layout-slash` | leading `.` (ru layout) → `/` + switch to us                                                                                                                                                             |
| `dsh-preview`      | serving workspace images at `/dsh-preview/<path>`                                                                                                                                                        |

Wiring: the profile `node_modules/<name>` is a **symlink** to the package in the fork (the
`TUI_FORK` pattern from `dsh-market.nix`; for gui-tweaks/prompt/layout-slash — their modules in
`modules/user/nix-maid/apps/`). An edit of the source in the fork applies with a plain F5 — the
server serves the bundles from disk, rev = sha1 of the content, `cache-control: no-cache`. No
rebuilds at all.

If the fork checkout is absent (a fresh machine before `git clone`), the plugin is skipped with a
warning — stale copies are not kept in Nix.

### 2. Foreign bundles — compact string maps (deliberate)

Four third-party packages (compiled code, not ours) contain Chinese UI strings that do not obey the
locale:

- `@0xsline/dsh-spotlight` (32 strings), `dsh-free-search` (6), `dsh-plugin-vetting` ×3 files (31),
  `dsh-file-upload` (2) — the map `modules/user/nix-maid/apps/dsh-web-en-assets/i18n.json`,
  applied by the `patch.mjs` patcher (idempotently, with markers and `.orig`).
- The base web bundle of dsh itself — the Nix package `packages/dsh/web-ui-en` (`patch.py` at
  build time); the profile `@deepseek-ai` symlink points at it (`dshAiStore` in dsh-market.nix).
- The TUI profile (`~/.dsh/profiles/tui`) — `dsh-tui-ru` (the same patch.mjs + map; hundreds of
  strings).

**Why not forks:** these packages are foreign compiled code with foreign dependencies. Example:
`dsh-file-upload` weighs 19 MB (nested pdfjs-dist, mammoth, markitdown-node, read-excel-file) —
vendoring that into your own repository freezes versions, drags in licenses and dependency trees, and
the edit there is 2 lines. A string map is version-tolerant (it skips missing keys) and does not
duplicate code. That is the right tool for foreign code; forks are for your own.

## Server-side slash commands without a browser part

Part of your commands are pure host plugins (only `apply` on the server, without `lib/client.js`):
they live directly in `/etc/nixos/modules/user/nix-maid/apps/<name>/` and are installed by an
ensure-script following the `dsh-mode.nix` pattern (copying files into the profile + an insert line
in `cordis.patch.yml`).

| Package               | Commands                                                    |
| --------------------- | ----------------------------------------------------------- |
| `dsh-mode`          | `/mode` — list/switch the default agent preset            |
| `dsh-session-tools` | `/rename`, `/status`, `/remember`, `/forget` — session utilities |

The client popup commands `/fork`, `/new`, `/goto`, `/model`, `/help` are a build-time
injection in `packages/dsh/web-ui-en/patch.py` (the commands anchor pattern).

## How to add your own plugin

1. Create a package in the fork: `packages/<name>/` with `package.json`
   (`"dsh": { "client": { "inject": [], "platform": "web" } }`, exports `.`/`./client`),
   `lib/index.js` (the host half, `apply`+`inject`), `lib/client.js` (the browser side,
   `window.__ModuleLoader__.load({ id, factory })`).
1. In `/etc/nixos` — a module of the gui-tweaks kind: the ensure-script runs
   `ln -sfn <fork>/packages/<name>` into the profile + appends the insert line to
   `cordis.patch.yml`; activation + a systemd user service.
1. `git -C ~/src/1st-level/@projects/dsh-web-ui push fork` — so the package reaches the other
   machines.

## Updating the fork against upstream

`git fetch upstream && git merge upstream/main` — your packages do not overlap with upstream (they
do not exist there); conflicts arise only if upstream changes shared code. The CSS-modules hash
classes (e.g. `_card_1b2ny_13`) are bound to the dsh version — after an upgrade, re-derive them by
grep in the served bundle.
