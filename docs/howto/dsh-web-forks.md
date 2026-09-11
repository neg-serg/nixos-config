# dsh web: forks instead of patches — current architecture

How dsh web GUI changes (profile `~/.dsh/profiles/web`) are arranged after the "patches → forks"
migration.

## Two mechanisms (there used to be five)

### 1. Own plugins — a fork repository (canonical source)

All plugins written for yourself live in the fork `~/src/1st-level/@projects/dsh-web-ui` (remotes
`fork` → `neg-serg/dsh-web-ui`, `upstream` → `zhu1090093659/dsh-web-ui`), under `packages/`:

| Package            | What it does                                                                                                                                                                                      |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `dsh-terminal-ui`  | the neg theme (navy glass, Iosevka, wide column)                                                                                                                                                  |
| `dsh-gui-tweaks`   | answers numbered in dialogs, bash-line wrapping, composer focus, todo_write → todo list, ask_user_question → question card, thoughts collapsed + code with a height cap, sidebar logo line hidden |
| `dsh-prompt`       | terminal placeholder `❯_` in the composer                                                                                                                                                         |
| `dsh-layout-slash` | leading `.` (ru layout) → `/` + switch to us                                                                                                                                                      |
| `dsh-preview`      | serving workspace images at `/dsh-preview/<path>`                                                                                                                                                 |

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
  `dsh-file-upload` (2) — the map `modules/user/nix-maid/apps/dsh-web-en-assets/i18n.json`, applied
  by the `patch.mjs` patcher (idempotently, with markers and `.orig`).
- The base web bundle of dsh itself — the Nix package `packages/dsh/web-ui-en` (`patch.py` at build
  time); the profile `@deepseek-ai` symlink points at it (`dshAiStore` in dsh-market.nix).
- The TUI profile (`~/.dsh/profiles/tui`) — `dsh-tui-ru` (the same patch.mjs + map; hundreds of
  strings).

**Why not forks:** these packages are foreign compiled code with foreign dependencies. Example:
`dsh-file-upload` weighs 19 MB (nested pdfjs-dist, mammoth, markitdown-node, read-excel-file) —
vendoring that into your own repository freezes versions, drags in licenses and dependency trees,
and the edit there is 2 lines. A string map is version-tolerant (it skips missing keys) and does not
duplicate code. That is the right tool for foreign code; forks are for your own.

## Server-side slash commands without a browser part

Part of your commands are pure host plugins (only `apply` on the server, without `lib/client.js`):
they live directly in `/etc/nixos/modules/user/nix-maid/apps/<name>/` and are installed by an
ensure-script following the `dsh-mode.nix` pattern (copying files into the profile + an insert line
in `cordis.patch.yml`).

| Package             | Commands                                                         |
| ------------------- | ---------------------------------------------------------------- |
| `dsh-mode`          | `/mode` — list/switch the default agent preset                   |
| `dsh-session-tools` | `/rename`, `/status`, `/remember`, `/forget` — session utilities |

The client popup commands `/fork`, `/new`, `/goto`, `/model`, `/help` are a build-time injection in
`packages/dsh/web-ui-en/patch.py` (the commands anchor pattern).

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

## dsh 0.1.5-rc.1: SDK breaks and the rows disabled meanwhile

dsh 0.1.5-rc.1 (2026-09-10) removed three SDK contracts the fork and `dsh-free-search` were written
against, so their host halves fail to import — and one failing loader entry refuses the WHOLE plugin
tree (`loader entries failed to apply`), leaving dsh unable to bind port 3080:

| Removed                                                                          | Replaced by                                                                                                             | Affected here                                                                                                                              |
| -------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `installSettingsSection` / `settingsNamespace` (`@deepseek-ai/dsh-settings`)     | the `ctx.settings` service method `installSection(owner, ns, schema, entry, hooks)`; a namespace is now the bare string | every fork plugin that owns a settings section; `dsh-mode` (in this repo, already ported)                                                  |
| the `apiProxy` host service (`@deepseek-ai/dsh-host-apiproxy`)                   | the Typert gateway (`ctx.typertGateway` on the host, `ctx.remote` on the client) plus per-domain Remote contributions   | `dsh-remote-web-ui` — its `/m/api` mobile channel (`apiProxy.sessions.*`, `apiProxy.events.mux`) needs a real redesign, not an import swap |
| `@deepseek-ai/dsh-client-runtime` (not published at 0.1.5, absent from the tree) | the new client module layout (`@deepseek-ai/dsh-client-modules`)                                                        | the browser halves of nine fork packages inject it                                                                                         |

Two more breakages were profile-configuration, not SDK: upstream 0.1.5 ships its own `file-upload`
transport row and its own `subagent-model-selection-settings` row, so the profile may not re-insert
either id — `packages/dsh/default.nix` renames the upstream `file-upload` row and the
`dsh-market.nix` patcher turns the settings insert into an id-targeted override.

The rows behind the unported plugins are disabled declaratively in `dsh-market.nix` (block
`0.1.5 SDK port pending`): `ssh`, `live-stats`, `remote-web-ui`, `describe-image`,
`ui-web-ui-settings`, `web-search-free`. Remove a line from that block and re-run the ensure script
(a rebuild or login does it) once its plugin is ported; the mobile remote-control channel of
`dsh-remote-web-ui` stays off until its gateway port lands.

Port state: the settings-API call sites of the fork are ported and the SDK devDependencies bumped to
`^0.1.5-rc.1` in the working tree of `~/src/1st-level/@projects/dsh-web-ui`, uncommitted — the
dependency install needs `@deepseek-ai/dsh-client-runtime` resolved first, and `dsh-remote-web-ui`
still builds against the removed `dsh-host-apiproxy`.

The step-by-step rewrite plan (token replacement rules, the `apiProxy` → Typert gateway mapping, the
row re-enable procedure and the verification protocol) is
[designs/dsh-0.1.5-fork-port.md](designs/dsh-0.1.5-fork-port.md).

## Getting the UI URL (`dsh-url`)

The web UI's `?token=` is a **per-process launch token**: dsh mints a fresh one on every start
(`nixos-rebuild`, `dsh-restart`, a crash restart), so a bookmark or an old tab stops authenticating
with `401`. The token exchange mints a **signed cookie that does survive restarts** (the signing
secret lives in the profile's credentials store), so a browser that has completed the handshake only
needs a reload afterwards — the token URL is for a fresh browser, a cleared cookie jar, or a
different authority than the one that minted the cookie.

`dsh-url` (a local-bin script) prints the live one straight from the service journal:

```sh
dsh-url          # loopback URL (the same one dsh opens in the browser)
dsh-url --open   # print it and hand it to xdg-open
dsh-url --copy   # print it and copy it to the clipboard
dsh-url --lan    # the LAN URL, when the log advertises one
```

Reach for it after a rebuild when the page answers `401` or spins.

## Seeing and switching the model

Upstream ships two surfaces over one per-session, provider-grouped directory
(`@deepseek-ai/dsh-client-ui-model-selection`; its README: "the `/model` popup or the composer's
model control"), and the deployment default lives in a third place
(`@deepseek-ai/dsh-agent-default-model`).

| Surface                       | How                                                                                                                                                                                                                                  |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Web, composer seat            | the model control next to the pending indicator — click for the grouped model + effort list (per session; a running step keeps the model it started with)                                                                            |
| Web, command                  | `/model` in the composer opens the same popup                                                                                                                                                                                        |
| Web, keyboard                 | `Ctrl+M` opens it too (the neg theme's shortcut, kept alongside the visible seat)                                                                                                                                                    |
| Web, default for new sessions | `~/.dsh/settings.yaml` → `agent-default-model: {provider, model, reasoningEffort}`                                                                                                                                                   |
| TUI                           | `/model` with **no arguments opens a picker**; `/model <provider/model\|spark-flash\|spark-pro> [off\|high\|max] [default]` switches (a trailing `default` also persists it); the status line always shows `provider/model · effort` |
| TUI, effort                   | `/effort off\|high\|max\|auto\|default`                                                                                                                                                                                              |

Model ids on the `deepseek-official` route (see the first-party
[API docs](https://api-docs.deepseek.com/) and the
[DeepSeek-V4.1-Flash model card](https://huggingface.co/deepseek-ai/DeepSeek-V4.1-Flash)); V4.1
Flash shipped 2026-09-10 and replaced every V4 Flash route:

| id                                          | what it serves now                                                                                                                      |
| ------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `deepseek-flash`                            | DeepSeek-V4.1-Flash — the canonical id to use (text + image, 1M context, continuously controllable reasoning effort 1–100)              |
| `deepseek-v4-flash`, `…-vision-exp`, `chat` | accepted legacy ids, but the V4 models are **retired**: every request is served by V4.1-Flash and billed at the Flash price             |
| `deepseek-v4-pro`                           | still a distinct model today; from 12:00 Beijing time (= 04:00 UTC) on 2026-09-14 it is **routed to V4.1-Flash** until V4.1 Pro appears |

`@deepseek-ai/dsh-llm-deepseek` ships advisory capability metadata per id, and the legacy rows still
describe V4-era limits: `deepseek-v4-flash` is listed as text-only, so the harness projects
attachments to `[Unsupported Image]` before dispatch, and only `deepseek-flash` declares
`systemPromptUpdate: in-history` (mid-conversation system messages). Capability metadata is advisory
— the wire model is the same either way. Unlisted ids still pass through as text-only routes; the
local Ollama routes come from `llm-pi-ai` in `settings.yaml`.

Note for the theme: `packages/dsh-terminal-ui` used to hide the composer model seat entirely
(`[data-composer-card] button[aria-haspopup="menu"]`) and left only `Ctrl+M`; the seat is visible
again — it is the discoverable surface, and the shortcut still works.
