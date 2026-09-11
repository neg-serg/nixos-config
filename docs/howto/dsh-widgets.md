# dsh-widgets — widgets in dsh (JSON tree + agent cards)

The `dsh-widgets` plugin adds general-purpose widgets to DeepSeek Harness (web profile): the `json`
tool with an expandable, syntax-highlighted tree right in the chat, plus readable cards for the
orchestration tools (`subagent`, `workflow`, `ralph`, `goal`, `jobs`, `list_agents`), which
otherwise fall back to the generic "Tool call" row with raw JSON.

## What is added

| Tool(s)                                | Card                                                                                                                                                                                                                                                                                                                                          |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `json`                                 | expandable tree with type highlighting, search, copy, "expand/collapse all" buttons, node/depth/size counters                                                                                                                                                                                                                                 |
| `subagent`, `subagent_fork`            | status (running / done / background task / launched / error), label from `description`, "background" mode, **full prompt** (collapsed by default: "Show prompt ▾" + character counter), output                                                                                                                                                |
| `workflow`                             | name, "N agents", parsing of `Return value:` and rendering of the result with the same JSON tree                                                                                                                                                                                                                                              |
| `ralph`                                | status (done / blocked / round limit), "N rounds", summary / evidence / nextSteps / blocker                                                                                                                                                                                                                                                   |
| `get_goal`/`create_goal`/`update_goal` | goal phase, objective, "rounds N/M" progress, activation, blocked banner                                                                                                                                                                                                                                                                      |
| `job_output`/`job_list`/`job_kill`     | job status (from `[status: …]`), id, output                                                                                                                                                                                                                                                                                                   |
| `list_agents`                          | table: id, status badge, label, parent/depth                                                                                                                                                                                                                                                                                                  |
| `cordis_inspect_list/query/self`       | output (`JSON.stringify`) rendered with the same JSON tree                                                                                                                                                                                                                                                                                    |
| `plugin_vet`                           | badges safe/low/medium/high, packages with risk badges, score, findings, [REVIEW]                                                                                                                                                                                                                                                             |
| `gavel_review`                         | lightweight markdown rendering of the report (headings/bullets)                                                                                                                                                                                                                                                                               |
| `memory` / `memory_recall`             | memory entries (`- [track/scope] text`) as a list with chips                                                                                                                                                                                                                                                                                  |
| `bash_live` (optional)                 | command + **live terminal**: output streams into the chat node as it runs (workflow-panel pattern: `session.append("tool/bash-live-*")` → `conversationEvents` → `bash-live` node with autoscroll); the full output is returned in the tool result. Registered only when `enableBashLive: true` in the deployment config (**off by default**) |

Plus two live DOM elements above the composer: the **activity strip** (running subagents +
background jobs + goal rounds from the session projections `subagentsByParent` / `jobsBySession` /
`goal`, updated by subscription) and a **"rounds N/M"** chip right in the GoalBar (completed goal /
blocked — banner).

The activity strip also hosts the **"what's running in bash" indicator**: while a bash call is
running, the strip ticks `bash: <first line of the command> · Ns` (the command is taken from the
chat projection by `data-chat-call-id`, the timer from the first observation of the call). This dsh
version has no output streaming (on the wire only `tool/call` → `tool/result`), so the live display
is limited to the command + running time; the output itself appears in the card on completion
(auto-expand + no truncation — `dsh-gui-tweaks` tweaks).

Invalid JSON is an **error card** (with line/column), not a failed call. Very large JSON is
truncated on the server with a "fragment shown" banner. In TUI/headless a textual summary works
(degradation by design).

## Subagent completion notifications (the "Unknown content block" fix)

When a background subagent settles (crashed / finished / refusal / done), the parent session
receives a message with `source.kind = "subagent-settled`. The stock UI projects it as a context
row, and all non-text blocks of the child's final message (`reasoning`, `tool-call`) are rendered as
**"Unknown content block"** with raw JSON. There is no slot for this, so the plugin does a DOM
transform:

- finds the notification row by `data-chat-flow-key` (the key is taken from the live `chat`
  projection — the same store the chat is rendered from);
- builds the card: a reason badge (crashed / completed / stopped / token limit / refusal / aborted),
  the child's short id, a summary, "Final message" — text + expandable "Reasoning" (open by default
  for short ones) and "🛠 tool-call" / "Call result";
- inserts the card before the row and hides the row (React does not see it; when the row is
  recreated, the MutationObserver re-applies the transform).

The data is read from the projection, not from DOM dumps, so there is no truncation. All text goes
through `textContent` (blocks are model output — untrusted).

## How widgets are built in dsh (research summary)

- dsh — "everything is a plugin" (cordis). A widget = **tool** (server) + **keyed toolview**
  (client).
- The tool projects a descriptor `{ kind: … }` in `output.presentationMeta`; it is saved in the
  `tool/result` meta, so replay redraws the card from the log without a re-invocation.
- A client plugin is `window.__ModuleLoader__.load({ id, factory })`, inside which
  `ctx.slots.register({ name: 'tool.call.toolview', key: '<tool name>', priority: -10 }, Component)`.
  The slot key is the **tool name on the wire** (an open set: any tool, including custom ones).
- `priority: -10` overrides the built-in row (the `dsh-gui-tweaks` pattern).
- Themes — only `--dsw-alias-*` variables (border-l1, bg-layer-2/3,
  label-primary/secondary/tertiary, state-success/warn/error/business-primary, …) — the light/dark
  theme is picked up automatically.
- Rendering — only `React.createElement` + text nodes, without `dangerouslySetInnerHTML` (the JSON
  value comes from model output and is considered untrusted).
- Installation — a plain directory in `~/.dsh/profiles/web/node_modules/` (no pnpm: the
  `@deepseek-ai` symlink does not survive pnpm writes) + a line
  `- insert: [{ id: widgets, name: dsh-widgets }]` in `~/.dsh/profiles/web/cordis.patch.yml`.

## Key finding: why "pretty" did not work out of the box

Orchestration tools (`subagent`, `workflow`, `ralph`, `goal`, `jobs`) **do not set
`presentationMeta`**, so their `block.meta` is always empty — the client only receives
`block.call.argsRaw` (arguments) and `block.content` (rendered text). The generic row simply outputs
them as "Tool call" + raw JSON. That is why their cards are client-side and parse `argsRaw` and
`content` (the text format is stable: `started subagent <id>`,
`started background subagent task <id>`,
`workflow "<name>" completed (N agents).\nReturn value:\n…`, etc.).

## Live bash output (`bash_live`) — entirely through the plugin

> **Status:** enabled in this deployment (`enableBashLive: true` in the `dsh-widgets` line of
> `cordis.patch.yml`; the plugin default stays `false`, see `lib/index.js`). The fix is applied: the
> `Session.append` patch + the `ignorable` flag in the plugin (see "Task" below), dsh rebuilt
> (generation 1186), `dsh.service` restarted. Verified: the config reaches the plugin
> (`dsh --profile web --dump-config`), `bash_live` is registered only under the flag,
> `session.append(…, { ignorable: true })` puts the marker on the envelope, the reader accepts it.
>
> **How to use (important):** the `neg` preset (anchored-tool-bootstrap) starts the session in phase
> 1 — on the wire only `bash` + `str_replace_editor`; after the first answer/call there is a
> promotion into Code Mode: a single `run_code` tool with the SDK from the **current** tool
> registry. `bash_live` lives in that registry (enabled by the flag since 12:09 on 19.08.2026), so
> it is available in **any** session — old or new — via `tools.bash_live` inside run_code (dispatch
> `tool/code-dispatch-start` → `bash_live`); on the wire it is not shown as a separate tool either
> in phase 1 or in Code Mode. Verified end-to-end (19.08.2026): a fresh session, promotion,
> `tools.bash_live({command})` → events `tool/bash-live-start|output|end` with `"ignorable": true`,
> the session survives loading. Sessions `session-1a5d8a15…`, `session-e8d372df…`,
> `session-f6daf551…` are alive format-wise (`Session.fromRestore` + preflight `ok:true`); the
> "death" of `e8d372df` at 12:17 was a stuck LLM turn on `gavel_review`, not a format problem.
>
> **Client fix (19.08.2026, later):** the "live terminal" card did not render — `bashLiveDefinition`
> in `lib/client.js` had no `kind` field. The runtime builds the context key via
> `conversationContextKey(definition.kind, id)` (`${kind.length}:${kind}${id}`), and with
> `kind === undefined` any incoming `tool/bash-live-*` threw a `TypeError` inside `acceptMatch`
> (caught in `[apiproxy] envelope listener threw` — the stream lived, the card did not). Added
> `kind: "bash-live"` (the node already returned `kind: "bash-live"`, and the slot is registered
> with the same key). The file is served per-request without a cache — a page refresh is enough.
> Re-run: events are written with `"ignorable": true`, the card folds and renders.

Stock `bash` does not stream output (on the wire only `tool/call` → `tool/result`). But the plugin
can work around that without editing the core: the `bash_live` tool starts the command via
`ctx.shell.start` (a live process handle, incremental `readOutput()` deltas — the same mechanism as
background jobs), and puts every chunk into the session via
`session.append("tool/bash-live-output", …)` — the same durable channel through which the workflow
tool emits `tool-workflow/*` for its panel. The `dsh-widgets` client registers a
`conversationEvents` definition (the `dsh-client-ui-workflow-run` pattern): the events
`tool/bash-live-start|output|end` fold into the `bash-live` chat node — a live terminal with
autoscroll, a "Running" badge and a final status. Replay-stable (nodes fold from the log).

Limitations: the event stream is capped at ~500 events / 16 KB per chunk (not everything is dumped
into the log — the full output is always in the tool result); for short commands the plain `bash` is
faster, so `bash_live` is documented as the tool for long commands (builds, installs, tests, logs).
`timeoutMs` works: the kill timer is implemented in the plugin (`proc.kill()`) — `ctx.shell.start`
does not set a timeout by itself.

The persistence contract: the `tool/bash-live-*` types are outside the `KNOWN_SESSION_EVENT_TYPES`
dictionary of the current harness (rc.6), and `Session.append()` cannot set the `ignorable` marker
on an event (the envelope is built as `{ type, seq, time, data, surfaceOp?, sourceEventSeqs? }` —
there is no `ignorable` option). The history reader refuses to open a log containing an unknown
non-ignorable event (`SessionFormatUnsupportedError` → the session looks "dead": it will not open,
the agent is unavailable).

Registering the three types in the shared set (`KNOWN_SESSION_EVENT_TYPES.add(type)` in `tools.js`
on plugin load) **does not protect in practice**: the plugin and `dsh-session-persistence` load
different instances of `@deepseek-ai/dsh-session` (profile `node_modules` vs harness), so the set
addition never reaches the reader, and every `bash_live` run writes non-ignorable events again. On
19.08.2026 three sessions died from this (`session-1a5d8a15…`, `session-e8d372df…`,
`session-f6daf551…`); they were repaired manually — the events were marked `"ignorable": true`
(backups in `~/.dsh/repair-backups/bash-live-ignorable/`). After that, `dsh-selfheal` was taught to
fix such logs automatically (see "Task", item 3) — manual repair is no longer needed.

## Task: fix `bash_live` for real — ✅ closed (19.08.2026)

Originally the task was assigned to the "Image previews in dsh-web" session (the `dsh-preview`
plugin), but the agent fixed it right in this repository. Closed completely: the patch is built and
applied, the flag is enabled in the deployment config.

1. ✅ **Done:** `Session.append()` can now put `ignorable: true` on the event envelope. The server
   patch was added to `packages/dsh/patch-widgets.py` (an edit of `dsh-session/lib/index.js`:
   `append(type, data, opts)` moves `opts.ignorable === true` into the envelope). The `dsh-widgets`
   plugin (`lib/tools.js`) passes `{ ignorable: true }` for all `tool/bash-live-*` — events are
   written with the marker, the reader skips them, the session does not die. The dead hack with
   `KNOWN_SESSION_EVENT_TYPES.add()` was removed (it did not work because of different module
   instances). The patch is applied when dsh is rebuilt (`postInstall` → `patch-widgets.py`).
1. ❌ **Not needed:** ripping out `bash_live` — the feature stays, now safe.
1. ✅ **Done earlier:** `dsh-selfheal` auto-repairs logs written before the fix (the semantic fix
   "`tool/bash-live-*` without `ignorable` → set `ignorable: true`" in `validateEvent` /
   `validateAndFixLines`; the fork checkout
   `~/src/1st-level/@projects/dsh-web-ui/packages/dsh-selfheal/lib/repair-core.mjs`, the module
   `modules/user/nix-maid/apps/dsh-selfheal.nix`). The selfheal report/log shows "semantic: N
   event(s) repaired (bash-live ignorable)".

**Application:** the patch landed in the store at the dsh rebuild (generation 1186); the
`enableBashLive: true` flag was added to the `dsh-widgets` line in `cordis.patch.yml` (declaratively
— `modules/user/nix-maid/apps/dsh-widgets.nix`, `ensureWidgets` writes the line with the config for
fresh profiles and migrates old lines without the config). The changes live in the repo; the next
`nh os switch` re-checks the line idempotently.

The final GUI check — ✅ done (19.08.2026): `bash_live` was run in a live session; in
`session.jsonl.zstd` the `tool/bash-live-*` events are written with `"ignorable": true`, the session
opens/reloads without `SessionFormatUnsupportedError`, the card folds into the chat node (after the
`kind` fix in `bashLiveDefinition` — see "Status"). The technical part was verified at the unit
level (see "Status" above); the client part was verified against the runtime code
(`conversationContextKey`/`acceptMatch`/the `conversation.chat.node` slot) and by a repeated run of
the tool.

## Server patches to dsh (staged, applied on dsh rebuild)

`packages/dsh/patch-widgets.py` (invoked in the `postInstall` of `packages/dsh/default.nix`,
exact-string replacements with an occurrence counter — on dsh version drift the build fails loudly):

1. **`model` parameter of the `subagent` tool** — the child model is overridden per call
   (`subagent(..., model: "deepseek-flash")`). The provider already resolves the model as
   `request.agentOptions?.model ?? parent.options.model` (dsh-subagent), so this is a clean
   pass-through. Verified functionally: `agentOptions` in the request to the provider = `{ model }`.
1. **`presentationMeta` on `subagent` / `workflow` / `ralph`** — a descriptor
   `{ kind: "subagent"|"workflow"|"ralph", … }` is put into the `tool/result` meta (structured
   fields instead of text parsing; the cards still parse text today — the meta is the path to
   hardening and replay stability).

## What was missing (the list of absent widgets)

An inventory of the 54 model-facing tools of this deployment: 20 have a keyed toolview (stock:
`bash`/`read`/`edit`/`write`/`rg`/`glob`/`web_search`/`web_fetch`/`todo_write`/`ask_user_question`/
`skill`/`cordis_*`; custom: `osm_*` → Leaflet, `visualize` → iframe,
`todo_write`/`ask_user_question` → the `dsh-gui-tweaks` cards). **33 fell into generic**; of these,
this plugin covers: `subagent`, `subagent_fork`, `workflow`, `ralph`, `get_goal`, `create_goal`,
`update_goal`, `job_output`, `job_list`, `job_kill`, `list_agents`,
`cordis_inspect_list/query/self`, `plugin_vet`, `gavel_review`, `memory`, `memory_recall`.

Still without cards:

- Trivial acks (a card adds little value): `send_message`, `interrupt_agent`, `report`,
  `exit_plan_mode`, `structured_output`, `schedule_*`.
- The rest: `pwsh` (a terminal — generic already renders a terminal-view), `read_image`,
  `str_replace_editor`, `read_document`, `describe_image`, `free_search_test`, `platform_search`,
  `recall`.

## How to activate and extend

- Activation: `systemctl --user restart dsh.service` (or the next `nixos-rebuild switch` — the
  `dsh-widgets.nix` module installs the plugin via an activationScript + systemd-oneshot).
- Code: `modules/user/nix-maid/apps/dsh-widgets/` (server `lib/index.js`, tool `lib/tools.js`,
  client `lib/client.js`).
- To re-apply a changed version from the module: delete
  `~/.dsh/profiles/web/node_modules/dsh-widgets` and restart dsh (the "copy only if the file is
  absent" pattern — local edits survive rebuilds).
- To add a card: in `lib/client.js` — a component + an entry in `KEYED_VIEWS`; for a custom tool
  with full `presentationMeta` — look at `dsh-osm` (the map) as the reference.
