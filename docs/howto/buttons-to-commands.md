# Replacing buttons with commands: plan

> Status: **in progress** — steps 1–14 are implemented (input field, messages, queue, sidebar,
> session commands, "always to bottom", auto-expansion of edits, header/sidebar → `/export` and
> `/export-md`, trajectory/panels/settings, workspace commands and mobile-control/update commands,
> memory button → `/mem`, step 13 — session search/list options/likes/scroll/upload → hotkeys
> `Ctrl+Alt+F/O/G/D/End/U` and the `/like`, `/dislike`, `/bottom`, `/upload` commands); the
> git-graph chip was removed, the page auto-reloads; step 11 — JSON highlighting in tool call
> output.

## Goal

Gradually remove from the dsh web GUI the buttons that duplicate textual commands (slash commands
`/…` in the input field, hotkeys, Enter, etc.), so that the interface can be driven from the
keyboard, like a terminal.

## Principle

- **Button → command.** For each button we first find (or add) a textual command/hotkey with the
  same function, and only then hide the button.
- **Hide, do not remove.** Buttons are hidden with CSS only (the DOM is untouched) — the change is
  reversible and does not break React.
- **If there is no command, add one**, then hide the button.
- Where the edits live: the personal **dsh-terminal-ui** skin (a fork of `dsh-web-ui`,
  `packages/dsh-terminal-ui/lib/client.js`), which already owns the look of the composer and injects
  a single `<style>` for the lifetime of the page.

## Mechanics (how to make changes)

1. Fork: `~/src/1st-level/@projects/dsh-web-ui` (workspace-link from `~/.dsh/profiles/web`, see
   `pnpm-workspace.yaml`).
1. Edits go directly into `packages/dsh-terminal-ui/lib/client.js` (the package has no `src/`;
   previous `theme(terminal-ui): …` commits were made this way).
1. **Two code layers** (a frequent cause of "doesn't work even though I did it"):
   - **client** (`lib/client.js`): the server serves it **live** from the fork (verified:
     `/plugins/dsh-terminal-ui/client.js` == the fork file; the rev hash is recomputed on the fly).
     No restart is needed; the page now **reloads itself** (rev auto-watcher, see below).
   - **host** (`lib/index.js`: commands, routes, service injections) is loaded once at dsh startup —
     after edits you need `systemctl --user restart dsh`.
1. Client check:
   `curl -s http://127.0.0.1:3080/plugins/dsh-terminal-ui/client.js | grep <new selector>`. Host
   check: `node --check lib/index.js` + restart + check in the `/` palette.
1. Commit to the fork: `theme(terminal-ui): …` (as in the history).

### Auto page reload on edits

`client.js` has a watcher: every 8 s it reads the fresh boot page (`/`) and `location.reload()`s the
tab when the rev of **any** client plugin has changed — **or** the service was restarted (fetch
failed and came back up). Skin edits therefore apply without F5, and after
`systemctl --user restart dsh` the page also reloads itself (and new host commands appear in the
palette, e.g. `/export-md`). Boot parsing: a regex over `window.__DSH_BOOT__ = {...}</script>`.

### Generated configs (rule)

`~/.dsh/profiles/web/cordis.patch.yml` is **generated** from
`modules/user/nix-maid/apps/dsh-market.nix` (activated at rebuild/login; the file carries a "Managed
by NixOS — do not edit" header). Any profile disabling/edits must be made **in the module**,
otherwise `nh os switch` will overwrite them. The same goes for disabling plugins:
`- id: <plugin> / disabled: true` in the module — and a dsh restart.

## Step 1 (done): the «+» button in the input field

**What it is.** The `+` button on the left side of the input field toggles the command menu (the
same list that opens when you type `/`). Markup from `@deepseek-ai/dsh-client-ui-conversation`
(InputBar):

```jsx
<div className="…tools">
  <Tooltip label={t("input.commands")}>
    <button aria-haspopup="listbox" aria-expanded={commandMenuOpen}
            onClick={onToggleCommandMenu}>
      <IconPlusOutline16 size={14} />
    </button>
  </Tooltip>
  …
</div>
```

**Replacement.** The `/` command in the input field duplicates its function — the button is
redundant. Hidden with a CSS rule in `dsh-terminal-ui`:

```css
[data-composer-card] button[aria-haspopup="listbox"] {
  display: none;
}
```

The selector is stable: `data-composer-card` is a permanent data attribute of the input card;
`aria-haspopup="listbox"` occurs in the conversation bundle exactly once. The scroll area and the
keyboard are unaffected.

**Verified.** After the edit the server immediately serves the updated bundle (rev `09810766aafd` →
`a744c35a19fa`).

## Step 2 (done): Send / Stop

**What it is.** The right side of the input field holds the main button: «Send»
(`aria-label="Send message"`); during a run it becomes «Stop» (`aria-label="Stop generating"`, a
separate button for an interruptible subagent run).

**Replacement.**

- **Send** is already duplicated by **Enter** in the input field (Shift+Enter — a new line,
  Ctrl+Enter — fast send / «insert into the queue»).
- **Stop** had no hotkey; **Esc** was added (a JS feature in `dsh-terminal-ui`): if a run is in
  progress (the «Stop» button is in the DOM) and no popups/modals are open, click it. Open menus are
  closed by Esc as before (the React handler fires first, our listener runs in the bubbling phase).

CSS:

```css
[data-composer-card] button[aria-label="Send message"],
[data-composer-card] button[aria-label="Stop generating"] {
  display: none;
}
```

## Step 3 (done): model selection

**What it is.** The model/effort selector on the right in the input field — a popup menu
(`aria-haspopup="menu"`), rendered into the `conversation.input.model` slot inside the input card
(no portal).

**Replacement.** The **Ctrl+M** hotkey opens the picker (a click on the hidden trigger); inside —
arrows + Enter (native menu navigation). The trigger is hidden with CSS:

```css
[data-composer-card] button[aria-haspopup="menu"] {
  display: none;
}
```

## Step 4 (done): buttons on messages and in the queue

**What it is.** The hover action panel of a message (Copy / Branch) and the queued-message buttons
(Edit / Delete / Steer). There were no hotkeys.

**Interaction model:** hotkeys act on the **last** message in the feed (a user decision) — no mouse
tracking.

**Replacement** (modifier combos; plain letters remain for typing):

| Hotkey               | Action                                                    |
| -------------------- | --------------------------------------------------------- |
| `Ctrl+Alt+C`         | copy the text of the last message (user or assistant)     |
| `Ctrl+Alt+B`         | branch the last message (assistant only, when available)  |
| `Ctrl+Alt+E`         | edit the last queued message (Enter — save, Esc — cancel) |
| `Ctrl+Alt+Backspace` | delete the last queued message                            |

Hidden with CSS (copy/branch only inside `[data-time-hover-root] [class$="_actions"]`, so the copy
buttons in code blocks are not affected):

```css
[data-time-hover-root] [class$="_actions"] [aria-label="Copy"],
[data-time-hover-root] [class$="_actions"] [aria-label="Copied"],
[data-time-hover-root] [class$="_actions"] [aria-label="Branch into a new conversation"],
button[aria-label="Edit queued message"],
button[aria-label="Remove queued message"],
button[aria-label="Steer queued message"] {
  display: none;
}
```

The hotkeys dispatch `.click()` on the hidden buttons — the stock application handlers run
(clipboard, fork, queue).

## Step 5 (done): sidebar — new chat and session switching

**What it is.** The «New session» buttons in the sidebar (there are two: the brand word and a
labeled icon button; both call `startSession`) and the session list (`role="treeitem"` with
`aria-selected`; workspace folder rows carry `aria-expanded`, so they are not confused with
sessions). There were no hotkeys.

**Replacement.**

| Hotkey                              | Action                                                                                                                         |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `/new` (command in the input field) | new chat                                                                                                                       |
| `Ctrl+Alt+N`                        | new chat (quick hotkey)                                                                                                        |
| `Ctrl+Alt+J`                        | next session in the sidebar list                                                                                               |
| `Ctrl+Alt+K`                        | previous session                                                                                                               |
| `Ctrl+Alt+W`                        | pick a workspace (when the input field is the «Choose workspace» trigger; Enter while it is focused also works out of the box) |

**The `/new` command — how it works.** dsh slash commands run on the host (`ctx.commands.register`),
while «new chat» is a client-side action, so a host command alone is not enough. Instead, the skin
registers a **client command source** (the `inputTriggers` service, the same pipeline as `/`): the
`new` candidate appears in the menu when `/` is typed, `matchEnter` handles a bare `/new` + Enter,
and `onPick`/`matchEnter` call `ctx.workspaces.startSession()` (the same thing the button does) and
strip the `/new` token from the field via the `slash/input-consume-token` event (as stock
ui-commands does). The heading of the separate menu group is hidden with CSS
(`[data-source="local"]`), so that `/new` reads as part of the command group.

CSS:

```css
button[aria-label="New session"] {
  display: none;
}
[data-source="local"] {
  display: none;
}
```

## Step 6 (done): session switching via commands + always to bottom

**Switch commands** (in the same client source as `/new`):

| Command           | Action                                                                                                      |
| ----------------- | ----------------------------------------------------------------------------------------------------------- |
| `/session <name>` | jump to a session: exact title match → prefix → substring → fallback by message content (`sessions.search`) |
| `/next`           | next session in the sidebar list                                                                            |
| `/prev`           | previous session                                                                                            |
| `/new`            | new chat (as before)                                                                                        |

Mechanics: the `onPick`/`matchEnter` of the source call `ctx.sessions.open(id)` / a click on the
list row; the token is stripped via `slash/input-consume-token`. Picking `/session` in the menu
leaves «/session» in the field — type the name and press Enter.

**Always to bottom.** Previously the chat restored the saved scroll position when a session was
opened (you landed in the middle). Now the skin is subscribed to `ctx.sessions.list` (store:
`current` — the active session): on any change of the current session — a sidebar click,
`Ctrl+Alt+J/K`, `/session`, `/next`, `/prev`, `/new` — the `[data-conversation-scroll]` scrollport
jumps to the end (a double rAF plus a retry after 700 ms to catch lazy-loaded content). The stock
handler then sees that we are at the bottom and keeps following the stream.

## Step 7 (done): code/file edits auto-expand

Tool-call cards are mounted collapsed (the body is **not** in the DOM until opened — CSS cannot
help, a click on the row is required). The auto-expansion (the same WeakSet approach as for
Think/commands/context) now also covers edit rows: the **`edit`**, **`write`** and **`code`**
variants open immediately; `read`/`search`/`bash` stay collapsed so that file contents do not flood
the column. A row collapsed manually is no longer auto-expanded (only new rows from new turns are).

## Step 8 (done): header and sidebar → commands

| Button                      | Where                                      | Replacement command                                                   | How it is hidden                                       |
| --------------------------- | ------------------------------------------ | --------------------------------------------------------------------- | ------------------------------------------------------ |
| Session log                 | header (`.nL4_yW_sessionLogButton`)        | `/export` — the stock `dsh-session-log-export` command (the same ZIP) | CSS                                                    |
| `⬇ md` (export to Markdown) | header (`.tui-export-btn`, a skin feature) | `/export-md` (added, see below)                                       | CSS                                                    |
| SSH                         | sidebar (`.mL8Uca_entry`)                  | `ssh`/`ssh-hosts`/`ssh-cluster`/`ssh-tunnel`                          | plugin enabled (dsh-ssh), the sidebar entry is visible |
| Collapse/expand sidebar     | sidebar (`.hHd-Xa_toggle`)                 | — (the panel is fixed)                                                | CSS                                                    |
| DeepSeek logo               | sidebar (`.hHd-Xa_brand`)                  | — (new session — `/new`, `Ctrl+Alt+N`)                                | CSS                                                    |

The shared CSS block (in the skin):

```css
.nL4_yW_sessionLogButton,
.tui-export-btn,
.hHd-Xa_toggle,
.hHd-Xa_brand {
  display: none;
}
```

The class hashes come from the pinned dsh release plus the fork build; after an upgrade, verify them
against the served bundles.

### The `/export-md` command

- **Host** (`lib/index.js`): `inject: ["webServer", "commands"]` +
  `ctx.commands.register({ name: "export-md", description: …, handler: … })`.
- **Client** (`lib/client.js`): the export logic was moved out of the feat-9 feature into a shared
  `exportMarkdown()` function at the `apply()` level; a `ctx.on("command/executed", …)` listener
  calls it on a successful `/export-md`. The function collects messages from the DOM
  (`.Md3f7G_flowItem`: user/assistant roots + tool rows `.Md3f7G_callRow`) and downloads a `.md` via
  a Blob.
- The `⬇ md` button stays in the code (hidden with CSS) — once the command is settled, the button
  code in feat-9 can be removed.

### git-graph (branch chip) — removed

The `data-gitgraph-chip` chip («Branch» / the current branch, e.g. «main») belongs to the
**`@linxin666/dsh-client-ui-git-graph`** plugin (cordis id `ui-git-graph`, part of
`dsh-web-ui-all`): a chip in the dock above the composer + a branch switching/creation popup + Git
Graph + `/git/*` host routes. Disabled in `dsh-market.nix`:

```nix
- id: ui-git-graph
  disabled: true
```

Gotcha: the chip does NOT disappear by itself — a dsh restart is required, and the edit must be in
the module (not in `cordis.patch.yml`), otherwise the chip returns after a rebuild. (That is exactly
what happened: the first attempt seemed to work, but there was no trace in the configs — the chip
stayed.)

## Step 9 (done): session-name autocomplete

The native `/` menu completes **command names** but not arguments (the `/`/`@` triggers only work on
a single token up to the first space). While `/session <part>` is in the input field, the skin shows
a custom popup above the composer with matching session titles (from `sessions.list` by
`displayTitle`, no id fallbacks):

- `↓`/`↑` — select; `Enter`/`Tab` — open the session (the token is stripped via
  `slash/input-consume-token`, like a bare `/session`); `Esc` — close; click — open.
- The keys are intercepted in the capture phase, so the React Enter handler does not send «/session
  …» as a message.
- `/session ` without an argument shows the first 8 sessions.

## Step 9b (done): trajectory, settings, panels

| Button               | Where                   | Replacement command                                           |
| -------------------- | ----------------------- | ------------------------------------------------------------- |
| Chat/Trajectory tabs | dock above the composer | `/trajectory` (clicks the matching tab; again — back to Chat) |
| Settings             | sidebar                 | `/settings` (clicks the hidden trigger)                       |
| Panels               | —                       | `/sidebar` / `/details` / `/panels` (the layout service)      |

Hidden with CSS: `.wSkVaW_tabs`, `button[aria-label="Settings"]`, `.VOzbGW_trigger`. A collapsed
sidebar leaves a 56 px icon rail — the rail is removed by a JS watcher (the right-panel track width
is dynamic; pure CSS does not suffice).

## Step 10 (done): workspace buttons, phone and update

**Workspace buttons in the sidebar** (rows of the Workspaces section):

| Button                                | Replacement command                                                                                                                                                    |
| ------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Workspace row (expand/select)         | `/workspace <name>` — switch: exact name → path → prefix → substring; opens the last real session of the workspace, an empty one gets a fresh session (`startSession`) |
| Ellipsis menu (Rename / Delete)       | `/workspace rename <name> <new>` · `/workspace delete <name>`                                                                                                          |
| «+» (New session in …)                | `/workspace <name>` + `/new`                                                                                                                                           |
| «Add workspace» in the section header | `/workspace add <path>` (absolute path; `create` directly, like the menu)                                                                                              |

In `/workspace rename` the old name is matched as the longest prefix of the rest of the line — names
with spaces work. Deletion happens without a confirmation dialog (a typed command is a deliberate
action; the folder and the logs are preserved — the same semantics as the button). Errors/success
are shown in a short status line above the composer (`.tui-ws-status`), like `/export-md`.

**Name autocomplete:** with `/workspace <part>` — a popup with workspace titles (`↓`/`↑`,
`Enter`/`Tab` — switch; `Esc` — close; `/workspace ` without an argument shows the first 8). The
`add`/`rename`/`delete` subcommand words suppress the popup. The same capture pattern as `/session`.

**Sidebar footer buttons** (the `@linxin666/dsh-remote-web-ui` plugin):

> Temporarily unavailable: the plugin is disabled while it is ported off the contracts dsh
> 0.1.5-rc.1 removed (see "dsh 0.1.5-rc.1: SDK breaks" in `dsh-web-forks.md`), so the buttons are
> absent and `/phone` / `/update` have nothing to click until then.

| Button                                          | Replacement command |
| ----------------------------------------------- | ------------------- |
| Phone («Mobile remote control», QR panel)       | `/phone`            |
| Update («Check for updates», self-update panel) | `/update`           |

Both open their panels by clicking a hidden button (`clickByLabel`, like `/settings`); closing uses
the stock panel buttons (the ✕, a click on the mask).

**Phone access over LAN.** dsh listens only on `127.0.0.1:3080`; a narrow LAN socket
`192.168.2.87:3080` is kept open by `systemd-socket-proxyd` (`dsh-lan-proxy.socket`, see `dsh.nix`),
which forwards to loopback. The firewall opens 3080 only on `net1`. The phone panel shows the URL
`http://192.168.2.87:3080` — this is the plugin `publicBaseUrl` setting in `~/.dsh/settings.yaml`
(`remote-web-ui`); the `/api` fence accepts that host through the `web-runtime` override in the
profile patch (generated by `dsh-market.nix`; the `!!js` value must be quoted — without quotes YAML
reads it as a flow collection and dsh crashes while parsing the overlay).

CSS:

```css
button[aria-label^="Workspace actions for"],
button[aria-label^="New session in "],
button[aria-label="Add workspace"],
button[aria-label="Mobile remote control"],
button[aria-label="Check for updates"] {
  display: none;
}
```

All of this is the client side of the skin — no dsh restart is needed.

## Step 11 (done): JSON highlighting in tool call output

Tool-call cards render the input/output (IN/OUT) as a single text node (`.o3BgMG_ioText` inside
`.o3BgMG_ioCard`). When that text parses as JSON (e.g. the output of `hyprctl -j`, `sensors -j`,
`systemctl -o json`, `nix flake metadata --json`), the `tui-jsonfmt` feature redraws it:

- **pretty-print** — 2-space indentation when the JSON was minified
  (`JSON.stringify(parsed, null, 2)`);
- **syntax highlighting** — keys (light steel), strings (green), numbers (gold), `true`/`false`/
  `null` (purple), punctuation (muted);
- **collapsing long output** — output > 4000 characters collapses to 9 lines; clicking the block
  expands it (the state is remembered per node).

Limits: non-JSON text is not touched; output > 200 KB is skipped (parsing on every re-render would
jank the UI). React rewrites the text node on re-renders, so the feature re-applies itself through a
MutationObserver (the same pattern as `tui-no-tps`).

Classes: `.tui-json`, `.tui-json-{punct,key,str,num,bool,null}`, `.tui-json-collapsed` (CSS in the
skin). This is a purely client-side feature (`client.js`) — no dsh restart is needed.

## Step 12 (done): memory button → `/mem`

**What it is.** The **dsh-memento** plugin mounts a floating `#mem-open` button («🧠 Memory»,
bottom-right) in the corner of the screen that opens/closes the memory-watching panel (entries,
budget, audit, proposals). The memento client header mentions an F9 hotkey, but F9 is not wired in
the published client — the only real trigger for the panel is the button.

**Replacement.** The **`/mem`** command (a skin client command source, like `/settings`): it clicks
the hidden `#mem-open` button (`toggleMemory()` → `document.getElementById("mem-open").click()`). A
second `/mem` — and the second click — closes the panel (the button is a toggle); inside the panel
the stock ✕ and Refresh work.

**Why not `/memory`.** dsh-memento already has a host command **`/memory`** (memory management:
`list`, `add`, `remove`, `consolidate`, `proposals`, `budgets`, `audit`, `export`, `import`). It is
registered in the `@deepseek-ai/dsh-web-app` bundle, which loads before the skin, so typing
`/memory` shows a host candidate in the `/` menu, and Enter on a bare `/memory` goes into the host
claim (it waits for an argument) instead of opening the panel. To avoid duplicating a menu entry and
breaking memory management, the panel command is called `/mem` — short and terminal, like the skin's
other commands. `/memory` remains the host command (the full management set), as visible in the
menu.

CSS:

```css
#mem-open {
  display: none;
}
```

The selector is stable: `#mem-open` is the permanent id of the injected button. The panel
(`#mem-drawer`) is untouched — it opens on the command and closes with the stock ✕. Purely a client
feature; no dsh restart is needed.

## Important: Russian layout → `e.code`

On the RU layout `e.key` returns Cyrillic (typing on the physical `N` key produces a Cyrillic
character), so **all** hotkeys are matched by `e.code` (the physical key, layout-independent). This
also applies to steps 3–4 (fixed in the same edit).

## Hotkey and command summary

| Action                              | Command                                                                                     |
| ----------------------------------- | ------------------------------------------------------------------------------------------- |
| Command menu                        | `/` in the input field                                                                      |
| Send                                | `Enter` (Shift+Enter — a new line; Ctrl+Enter — insert into the queue)                      |
| Stop                                | `Esc` (only while running, with no menus open)                                              |
| Model selection                     | `Ctrl+M` (arrows + Enter inside)                                                            |
| Copy the last message               | `Ctrl+Alt+C`                                                                                |
| Branch the last message             | `Ctrl+Alt+B`                                                                                |
| Edit the last queued message        | `Ctrl+Alt+E`                                                                                |
| Delete the last queued message      | `Ctrl+Alt+Backspace`                                                                        |
| New chat                            | `/new` in the input field **or** `Ctrl+Alt+N`                                               |
| Go to a session                     | `/session <name>`                                                                           |
| Session autocomplete                | `/session <part>` + `↓`/`↑`, `Enter`/`Tab`, `Esc`                                           |
| Next / previous session             | `/next` / `/prev` **or** `Ctrl+Alt+J` / `Ctrl+Alt+K`                                        |
| Pick a workspace                    | `Ctrl+Alt+W` (or Enter in the trigger)                                                      |
| Session log (ZIP)                   | `/export`                                                                                   |
| Export the conversation to Markdown | `/export-md`                                                                                |
| Switch workspace                    | `/workspace <name>` (or `/workspace <part>` + `Enter`/`Tab` on the popup)                   |
| Add workspace                       | `/workspace add <path>`                                                                     |
| Rename workspace                    | `/workspace rename <name> <new>`                                                            |
| Delete workspace                    | `/workspace delete <name>`                                                                  |
| Mobile control (QR)                 | `/phone`                                                                                    |
| Check for updates                   | `/update`                                                                                   |
| Memory panel (dsh-memento)          | `/mem` (again — close); `/memory` — the host management command                             |
| Hotkey help                         | `?` as the first character of the input line (typed, not pasted; again — hide, Esc — close) |

## Step 14 (done): hotkey help via «?»

Typing a question mark as the **first character** of an input line (typing specifically —
`inputType` `insertText`; pasting does not trigger it) opens a popup above the composer with all GUI
hotkeys and commands. Pressing «?» again (or `Esc`) closes the popup and removes the «?» itself; if
you type text after «?» (e.g. «?sessions»), the popup closes while the text stays — «?» behaves like
an ordinary question mark.

Hotkeys are **collected into one registry**, `window.__DSH_HOTKEYS__` (a lazy global: whoever loads
first creates it; plugin order does not matter). Each fork plugin registers its bindings via
`.add([{ group, keys, action }])` at `apply`:

- `dsh-terminal-ui` — its own hotkeys (steps 2–5, 13: `Ctrl+M`,
  `Ctrl+Alt+C/B/E/Backspace/N/J/K/W/F/O/G/D/End/U`, `Ctrl+F`, `Tab`, `Esc`) and slash commands (the
  «Commands» group);
- `dsh-gui-tweaks` — the composer emacs keys (the «Input» group: `C-a/C-e`, `C-k/C-u`,
  `CapsLock+W (C-w)`, `M-f/M-b`, `C-y`, `C-t`, `C-_/C-/`, …).

The popup re-reads the registry on every open, so new registrations (including from plugins loaded
later) appear without edits. The code lives in `dsh-terminal-ui/lib/client.js` (the «? composer help
popup» feature + the registry factory at the top of the file); the gui-tweaks registration is in
`dsh-gui-tweaks/lib/client.js` (the beginning of `apply`).

## Locale: selectors by `aria-label`

The GUI runs in the **English** locale (browser `en-US`), so all `aria-label` selectors use the
English bundle strings («Send message», «Stop generating», «Branch into a new conversation», …):

```css
[data-composer-card] button[aria-label="Send message"],
[data-composer-card] button[aria-label="Stop generating"] { … }
```

If the bundle locales change, update the selectors (an early version of steps 2/4/5 was written for
zh-CN and silently did not work in the English GUI; the Chinese duplicates were later removed as
dead weight).

## Candidates for the next steps (for approval)

| Button                                                      | Where                        | Replacement command                                                         | Status                            |
| ----------------------------------------------------------- | ---------------------------- | --------------------------------------------------------------------------- | --------------------------------- |
| «+» (command menu)                                          | input field, left            | `/`                                                                         | ✅ implemented                    |
| Send / Stop                                                 | input field, right           | Enter / Esc                                                                 | ✅ implemented                    |
| Model selection                                             | input field, right           | Ctrl+M                                                                      | ✅ implemented                    |
| Copy / Branch / Edit / Delete                               | on messages and in the queue | Ctrl+Alt+C/B/E/Backspace                                                    | ✅ implemented                    |
| New chat / session list                                     | sidebar                      | `/new`, Ctrl+Alt+N / Ctrl+Alt+J,K                                           | ✅ implemented                    |
| Workspace picker                                            | input field                  | Ctrl+Alt+W                                                                  | ✅ implemented                    |
| Session log                                                 | header                       | `/export`                                                                   | ✅ implemented                    |
| `⬇ md`                                                      | header                       | `/export-md`                                                                | ✅ implemented                    |
| SSH                                                         | sidebar                      | `ssh`/`ssh-hosts`/`ssh-cluster`/`ssh-tunnel`                                | ✅ plugin disabled                |
| Collapse/expand sidebar                                     | sidebar                      | — (the panel is fixed)                                                      | ✅ hidden                         |
| DeepSeek logo                                               | sidebar                      | — (new session — `/new`)                                                    | ✅ hidden                         |
| git-graph branch chip                                       | dock above the composer      | — (git — in the terminal)                                                   | ✅ plugin `ui-git-graph` disabled |
| Workspace buttons (rows, rename/delete, «+», Add workspace) | sidebar                      | `/workspace` / `/workspace rename` / `/workspace delete` / `/workspace add` | ✅ implemented (step 10)          |
| Phone («Mobile remote control»)                             | sidebar footer               | `/phone`                                                                    | ✅ implemented (step 10)          |
| Update («Check for updates»)                                | sidebar footer               | `/update`                                                                   | ✅ implemented (step 10)          |
| Memory button (`#mem-open`, dsh-memento)                    | floating, bottom-right       | `/mem`                                                                      | ✅ implemented (step 12)          |
| Session search («Search sessions»)                          | sidebar                      | `Ctrl+Alt+F`                                                                | ✅ implemented (step 13)          |
| Session list options («View options»)                       | sidebar                      | `Ctrl+Alt+O`                                                                | ✅ implemented (step 13)          |
| Like/dislike a response («Good/Bad response»)               | on messages                  | `Ctrl+Alt+G/D`, `/like`, `/dislike`                                         | ✅ implemented (step 13)          |
| Scroll to bottom («Back to bottom»)                         | chat                         | `Ctrl+Alt+End`, `/bottom`                                                   | ✅ implemented (step 13)          |
| File upload («Upload file», dsh-file-upload)                | composer                     | `Ctrl+Alt+U`, `/upload`                                                     | ✅ implemented (step 13)          |

The order and the scope are by choice: we fix one button at a time, and after each one — a GUI check
and a commit.
