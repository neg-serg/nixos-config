# DSH hooks: rules-injector / compaction-todo-preserver / category-skill-reminder / agent-usage-reminder

Design for DSH web 0.1.0-rc.6 (store `@deepseek-ai`). Verified by reading the built code in
`/nix/store/zvfrqpjr7x0w0ns3m53l9sx05wf24scw-dsh-web-en-0.1.0-rc.6`, the sources of
`omo-opencode/src/hooks`, the `dsh-web-ui` fork and the `/etc/nixos` modules (`dsh-mode`,
`dsh-liangshen-fork`, `dsh-gui-tweaks`).

## Key DSH facts (what the assessment is based on)

- DSH is a cordis platform. A plugin exports `{ name, inject?, apply(ctx, config) }` and is mounted
  as a row in `cordis.patch.yml`:
  ```yaml
  - insert:
      - id: rules-injector
        name: dsh-rules-injector
        config: { rulesDir: "rules" }
  ```
  Host plane: `~/.dsh/profiles/web/cordis.patch.yml` + package in
  `~/.dsh/profiles/web/node_modules/<name>`. Agent plane (what we need for per-session hooks):
  `~/.dsh/.agent-presets/neg/agent.cordis.yml` (preset `neg`).
- Confirmed events (`ctx.on`): `tools/pre-execute`, `tools/execute`, `tools/post-execute`,
  `tools/result`, `session/event`, `session/created`, `agent/pre-step`, `agent/created`,
  `fs/observed`, `fs/write-intent`, `fs/edit-intent`, `system-prompt/assemble`, `subagent/start`,
  `subagent/end`.
- `tools/post-execute(exec, result, next)`: `next()` returns
  `{ kind, value, additionalContexts?, feedback? }`; context can be prepended — the precedent is
  `dsh-repeat-tool-reminder` (guard, mounted in `dsh-base`).
- `agent/pre-step({ agent, messages, signal }, next)`: `next()` yields `decision.messages` —
  synthetic messages are appended there before the step. Precedent — `dsh-tool-skill` (injects skill
  text).
- `session/event(session, event)`: event.type comes from `KNOWN_SESSION_EVENT_TYPES`; there are
  `todo/write`, `compaction/start`, `compaction/end`, `compaction/summary`, `compaction/prune`.
- `todo_write` (`dsh-tool-todo`) does `session.append("todo/write", { todos })` on every call — the
  todo state lives in the session log; compaction collapses it. Recovery is a repeated `append`.
- Skills: the `ctx.skills` service (`ctx.skills.snapshot/get`) — for categories/list.
- Delegation: `dsh-tool-subagent` registers `subagent` and `subagent_fork`.

Conclusion: all four features are a **server plugin (cordis) in the agent preset**, not a client
plugin (the browser has no tool lifecycle / session log) and not a fork patch (the required hooks
already exist — none are missing). docs-only is only a cheap v0 for reminders.

______________________________________________________________________

## 1. rules-injector (rules/\*.md + alwaysApply, injection on read)

- **Feasibility:** server plugin. The `tools/post-execute`, `fs/observed`, `session/event` hooks
  already exist; the omo logic (finder/parser/matcher/dedup) is ported.
- **Integration point:** the `neg` agent preset (`agent.cordis.yml`). Trigger — `tools/post-execute`
  for `read`/`write`/`edit`/`str_replace_editor`; take the file path from `result.value.path` (or
  `exec.arguments.file_path`). Optionally `fs/observed(target, observation, actor)` for the fact
  "file read". The "already injected in this session" cache is cleared via `session/event`
  (`compaction/start`, `session/end-seed`).
- **Sketch:**

```js
import { readdirSync, readFileSync } from "node:fs";
import { join, relative, dirname } from "node:path";

export const name = "rules-injector";
export function apply(ctx, config = {}) {
  const root = () => ctx.workspace ?? process.cwd();      // or agent.session.header.cwd
  const cache = new Map();                                 // sessionID -> Set(realPath)

  function scanRules(dir) {                                // simplified: rules/*.md + AGENTS.md
    const out = [];
    for (const f of readdirSync(dir, { withFileTypes: true })) {
      if (f.name === "AGENTS.md") out.push(join(dir, f.name));
      if (f.name === "rules" && f.isDirectory())
        for (const r of readdirSync(join(dir, f.name)))
          if (r.endsWith(".md")) out.push(join(dir, "rules", r));
    }
    return out;
  }
  function match(rulePath, filePath) {                     // alwaysApply or glob from frontmatter
    const text = readFileSync(rulePath, "utf8");
    const m = text.match(/^---\n([\s\S]*?)\n---/);
    if (!m) return true;                                   // no frontmatter = always
    const fm = m[1];
    if (/alwaysApply:\s*true/.test(fm)) return true;
    const g = fm.match(/glob:\s*(\S+)/)?.[1];
    return g ? new RegExp("^" + g.replace(/\*\*/g, ".*").replace(/\*/g, "[^/]*") + "$")
                   .test(filePath) : false;
  }

  ctx.on("tools/post-execute", async (exec, result, next) => {
    const downstream = await next();
    if (!["read","write","edit","str_replace_editor"].includes(exec.name)) return downstream;
    const filePath = result.value?.path ?? exec.arguments?.file_path;
    if (!filePath) return downstream;
    const rel = relative(root(), filePath);
    const sessionID = exec.agent?.session?.id;
    if (!sessionID) return downstream;
    let seen = cache.get(sessionID);
    if (!seen) { seen = new Set(); cache.set(sessionID, seen); }
    const additions = scanRules(root())
      .filter(rp => !seen.has(rp) && match(rp, rel))
      .map(rp => { seen.add(rp); return readFileSync(rp, "utf8"); });
    if (additions.length === 0) return downstream;
    return { ...downstream,
      additionalContexts: [...(downstream.additionalContexts ?? []), ...additions] };
  });

  ctx.on("session/event", (session, event) => {
    if (event.type === "compaction/start" || event.type === "session/end-seed")
      cache.delete(session.id);
  });
}
```

- **Effort:** M. The logic is simple, but it needs: a full frontmatter parser, an honest glob (no
  picomatch — write a mini-matcher or add a dependency), finder/matcher/dedup tests, cache cleanup.
  If limited to `alwaysApply` and `rules/*.md` + `AGENTS.md` names without arbitrary globs — S.
- **Risk:** scan order and dedup must be deterministic; do not inject the rules for the `read` of
  the rule file itself (otherwise recursion/junk).

______________________________________________________________________

## 2. compaction-todo-preserver (the todo list survives compaction)

- **Feasibility:** server plugin. Everything needed already exists: `session/event` with
  `todo/write`, `compaction/start`, `compaction/end`; recovery is a repeated
  `session.append("todo/write", { todos })`. The omo Atlas-bootstrap wrapper is not needed in DSH
  (no Atlas).
- **Integration point:** agent preset; one `session/event` handler.
- **Sketch:**

```js
export const name = "compaction-todo-preserver";
export function apply(ctx) {
  const latest = new Map();   // sessionID -> todos[]
  const snapshot = new Map(); // sessionID -> todos[] as of compaction/start

  ctx.on("session/event", (session, event) => {
    if (event.type === "todo/write") {
      latest.set(session.id, event.data.todos);
    } else if (event.type === "compaction/start") {
      const todos = latest.get(session.id);
      if (todos && todos.length) snapshot.set(session.id, todos);
    } else if (event.type === "compaction/end") {
      const todos = snapshot.get(session.id);
      snapshot.delete(session.id);
      if (todos && todos.length) session.append("todo/write", { todos });
    } else if (event.type === "session/end-seed") {
      latest.delete(session.id); snapshot.delete(session.id);
    }
  });
}
```

- **Effort:** S (~50 lines + test). The main question is idempotency: if compaction kept
  `todo/write` in the summary, a repeated append will add a duplicate. Safe option: on
  `compaction/end` always re-append (the model sees the actual list; a duplicate in the log is
  harmless because the projection takes the last `todo/write`).
- **Verification:** an "empty" compaction must not create a todo list out of nothing; a session
  restart/reset clears the Map (`session/end-seed`).

______________________________________________________________________

## 3. category-skill-reminder (remind skills for the delegation category)

- **Feasibility:** server plugin; **a docs-only v0 is possible** (one line in
  system-prompt/agent-guards). The full runtime variant uses `tools/post-execute` (a counter of
  "working" calls) + `agent/pre-step` (reminder injection) + `ctx.skills.snapshot()`.
- **Integration point:** agent preset. Trigger — 3+ direct calls of
  `read`/`write`/`edit`/`str_replace_editor`/`bash`/`rg`/`glob` without delegation
  (`subagent`/`subagent_fork`).
- **Sketch:**

```js
export const name = "category-skill-reminder";
export function apply(ctx, config = {}) {
  const WORK = new Set(["read","write","edit","str_replace_editor","bash","rg","glob"]);
  const DELEGATE = new Set(["subagent","subagent_fork"]);
  const state = new Map(); // agent.id -> {delegated, work, pending, shown}

  ctx.on("tools/post-execute", async (exec, _result, next) => {
    const downstream = await next();
    const id = exec.agent?.id; if (!id) return downstream;
    const s = state.get(id) ?? { delegated:false, work:0, pending:false, shown:false };
    state.set(id, s);
    if (DELEGATE.has(exec.name)) { s.delegated = true; s.pending = false; return downstream; }
    if (WORK.has(exec.name)) s.work += 1;
    if (s.work >= 3 && !s.delegated && !s.pending && !s.shown) s.pending = true;
    return downstream;
  });

  ctx.on("agent/pre-step", async ({ agent, messages, signal }, next) => {
    const decision = await next();
    if (decision.kind === "reject") return decision;
    const s = state.get(agent.id);
    if (!s?.pending) return decision;
    s.pending = false; s.shown = true;
    const snap = await ctx.skills.snapshot({ cwd: agent.session.header.cwd, signal });
    const text = "[Category+Skill Reminder] Delegate via subagent with load_skills for the "
      + "category. Available: " + snap.skills.map(x => x.name).join(", ");
    return { ...decision, messages: [...decision.messages, createUserMessage({ content: text, source: { kind: "plugin" } })] };
  });
}
```

- **Effort:** S-M. S if doing docs-only (a line in the preset); M for the runtime hook
  - counter test. Categories/skill mapping are set via config.
- **Nuance:** in DSH delegation has no `category` field like omo; the "category → skills" mapping
  will have to live in the plugin config (or parse `config/agent-presets`).

______________________________________________________________________

## 4. agent-usage-reminder (reminder to use subagents)

- **Feasibility:** server plugin — an exact copy of the `dsh-repeat-tool-reminder` pattern
  (`tools/post-execute` + `additionalContexts`). A docs-only v0 is possible.
- **Integration point:** agent preset; `tools/post-execute`.
- **Sketch:**

```js
export const name = "agent-usage-reminder";
export function apply(ctx, config = {}) {
  const SEARCH = new Set(["rg","glob","web_search","bash"]); // direct "manual" searches
  const AGENTS = new Set(["subagent","subagent_fork"]);
  const MAX = config.maxReminders ?? 3;
  const state = new Map(); // sessionID -> {agentUsed, reminded}

  ctx.on("tools/post-execute", async (exec, _result, next) => {
    const downstream = await next();
    const id = exec.agent?.session?.id; if (!id) return downstream;
    const s = state.get(id) ?? { agentUsed:false, reminded:0 };
    state.set(id, s);
    if (AGENTS.has(exec.name)) { s.agentUsed = true; return downstream; }
    if (!SEARCH.has(exec.name) || s.agentUsed || s.reminded >= MAX) return downstream;
    s.reminded += 1;
    return { ...downstream, additionalContexts:
      [...(downstream.additionalContexts ?? []), REMINDER] };
  });

  ctx.on("agent/pre-step", ({ agent, messages }, next) => {   // new user turn = reset
    if (messages.some(m => m.source?.kind === "user")) state.delete(agent.id);
    return next();
  });
}
```

- **Effort:** S (~70 lines + test). Maximum reuse — copy the `repeat-tool-reminder` skeleton (Config
  schema, `additionalContexts`, `agent/pre-step`).
- **Nuance:** the SEARCH list must be calibrated for DSH (`rg`/`glob`/read-only `bash`) so that
  ordinary edits are not spammed by the reminder.

______________________________________________________________________

## Recommended order

1. **agent-usage-reminder** — S, ready `repeat-tool-reminder` template, immediately visible benefit.
1. **compaction-todo-preserver** — S, one `session/event`, closes the pain of losing todos during
   compaction.
1. **rules-injector** — M (or S without arbitrary glob), the most valuable one, but requires
   parser/matcher/tests; do it after the server-plugin pattern is proven on 1–2.
1. **category-skill-reminder** — M; a docs-only v0 (a line in the system prompt) can be shipped
   right away, the runtime hook later.

The common deployment step on odin for each plugin: a package in
`modules/user/nix-maid/apps/<name>/` (`package.json` + `lib/index.js`), an ensure script modeled on
`dsh-mode.nix` copies it to `~/.dsh/profiles/web/node_modules/<name>`; the row is added **not** to
the profile `cordis.patch.yml`, but to `~/.dsh/.agent-presets/neg/agent.cordis.yml` (or to
`dsh-liangshen-fork/agent.cordis.yml` and the sync script), then
`systemctl --user restart dsh.service`. We do not touch any upstream/fork repository files.
