# Boulder — todo-continuation enforcer for DSH

Sources: /etc/nixos/docs/howto/agent-guards.md item 6; omo
packages/omo-opencode/src/hooks/todo-continuation-enforcer/ (constants.ts, handler.ts,
idle-event.ts, continuation-injection.ts, non-idle-events.ts, session-state.ts, compaction-guard.ts,
stagnation-detection.ts, countdown.ts, types.ts); DSH types @deepseek-ai/dsh-agent, dsh-session,
dsh-tool-todo, dsh-session-projection, dsh-llm (createUserMessage); example dsh-plan-mode.

## 1. Behavioral specification

Goal: when the agent goes idle while unclosed tasks remain in the todo, the harness itself wakes the
agent with a system directive and makes it continue working until the tasks are done. This is the
"Sisyphus stone": the agent must not stop.

### Triggers

- Main trigger — the agent going idle: the DSH event agent/status with status === "idle". On it the
  check and the countdown start.
- Stop events cancel an already running countdown and reset part of the state: a new user message,
  an assistant message, a tool-call (message.updated, message.part.updated, message.part.delta,
  tool.execute.before/after, agent/status → running).
- session.error with AbortError / MessageAbortedError sets wasCancelled and cancels the countdown; a
  token-limit or non-retryable request error (400/422 + isRetryable:false) sets the corresponding
  flag and stops the loop.

### Countdown — 2 seconds

- A successful check does NOT inject immediately: startCountdown() shows the toast "Resuming in
  Ns... (K tasks remaining)", TOAST_DURATION_MS = 900ms, tick 1s.
- COUNTDOWN_SECONDS = 2: after 2000ms the countdown is cancelled and injectContinuation() is called.
- COUNTDOWN_GRACE_PERIOD_MS = 500: a user message in the first 500ms after the countdown starts is
  ignored (protection against the race "we are already counting while the user is still typing").
  Later — the countdown is cancelled, no injection.
- ABORT_WINDOW_MS = 3000: if an abort was recorded less than 3s ago, idle is skipped once (do not
  hammer right after a cancellation).

### Backoff and cooldown

- CONTINUATION_COOLDOWN_MS = 5000: the minimum interval between two injections into one session
  (also passed as semanticDedupeHoldMs to the gate — do not spawn duplicates within 5s).
- Exponential backoff on repeated failures: effective cooldown = COOLDOWN_MS * 2 \*\*
  min(consecutiveFailures, 5) → 5s, 10s, 20s, 40s, 80s, 160s (base ×2, cap ×32).
- MAX_CONSECUTIVE_FAILURES = 5: after 5 failed injections in a row injections stop; a retry is
  allowed only after FAILURE_RESET_WINDOW_MS = 5 * 60 * 1000 (a 5-minute pause), with the counter
  reset to 0.
- ⚠️ Divergence from the backlog: agent-harness-features.md and agent-guards.md say "base 30s, ×2".
  In the omo code the exponent base is 5s (CONTINUATION_COOLDOWN_MS). Decide before implementation
  (see risks): for DSH I recommend following the omo code (5s) unless a literal port of the backlog
  text is required.

### Stagnation detection — max 3

- Counted on each idle after a successful injection: if the next check saw no progress on the todo,
  stagnationCount += 1.
- Progress = a decrease in incompleteCount, an increase in the number of completed, or a change in
  the snapshot {id → status} (changing only content/priority does NOT count as progress — omo issue
  #4013).
- When stagnationCount >= MAX_STAGNATION_COUNT = 3, injection stops for the session (the agent
  "responds to the directive but does not move the tasks"). Reset — on any progress.

### Compaction guard — 60 seconds

- COMPACTION_GUARD_MS = 60_000. On a compaction event the guard is armed with a new epoch.
- While the guard is active and the epoch has not been acknowledged by the agent, the idle injection
  is skipped: right after compaction the context has just been rebuilt, and an immediate directive
  breaks the recovery. The guard is acknowledged when agent-info appears on the resolved agent;
  after ack or 60s injection is allowed.

### When NOT to inject (full list)

1. allTodosCompletedAt is set (everything is already closed).
1. The session is in recovery (isRecovering).
1. wasCancelled (an abort happened).
1. A sync-subagent has already returned a result to the parent (handedBackSyncSessions).
1. tokenLimitDetected — a retry would worsen the context overflow.
1. unrecoverableErrorDetected — a repeated directive would assemble the same request.
1. An abort happened less than 3s ago (ABORT_WINDOW_MS).
1. There are running/pending background tasks of the session or a pending parent-wake.
1. The last assistant message is aborted (API fallback).
1. Waiting for a user answer (hasUnansweredQuestion).
1. An answer to the internal continuation directive is expected
   (latestAssistantTurnBlocksInternalPrompt).
1. Todo is empty or incompleteCount == 0.
1. inFlight — an injection is already in progress.
1. consecutiveFailures >= 5 and 5 minutes have not passed.
1. The cooldown has not elapsed yet.
1. The last message is a compaction marker.
1. The agent is in skipAgents (omo: prometheus, compaction, plan; in DSH — the corresponding
   system/subagent roles).
1. The compaction guard is active for the current epoch (or a compaction without a resolved agent).
1. isContinuationStopped(sessionID) — an external stop of the continuation.
1. continuationBlockReason — a pause at the turn boundary (directive-response or user-interruption).
1. The agent has no write permission (edit/write is not deny/false).
1. Fetch of messages/todo failed — skip safely (do not inject blindly).

## 2. Integration design (DSH layer)

DSH is a Cordis plugin in the web profile. The host half, apply(ctx), subscribes to events; the
browser client.ts only draws the toast/indicator.

### Files to add (in the dsh-web-ui fork, packages/dsh-boulder/)

- package.json — name @deepseek-ai/dsh-boulder, exports . and ./client, dsh.client.platform: "web",
  peerDeps on dsh-agent/dsh-session/dsh-llm/dsh-tool-todo/cordis.
- src/index.ts → lib/index.js — host: apply + state-store + all the logic.
- src/client.ts → lib/client.js — browser: window.__ModuleLoader__.load(...), renders the
  countdown-toast/status.
- src/constants.ts — all the constants + CONTINUATION_PROMPT.
- src/session-state.ts — per-session Map (a port of the omo session-state.ts logic).
- src/types.ts — SessionState, ResolvedAgentInfo.
- test/\*.test.ts — on @deepseek-ai/dsh-agent-loop-testkit.

### Detecting idle

ctx.on("agent/status", ({ agent, status }) => ...) — a Cordis emit event, scope-filtered. When
status === "idle", call handleSessionIdle(agent). The reverse transition status === "running"
cancels the countdown (the analog of non-idle-events).

### Detecting unclosed todos

Two paths:

1. Projection (preferred): ctx.sessionProjections.snapshot(agent.session).values.todos → TodoItem[]
   | null (the last todo/write, last-wins). The projection is registered by dsh-tool-todo; if the
   service is not loaded yet — fallback.
1. Fallback without dependencies: fold agent.session.events and take the last todo/write:
   events.filter(e => e.type === "todo/write").at(-1)?.data.todos.

incomplete = todos.filter(t => t.status !== "completed").length (in DSH the statuses are only
pending | in_progress | completed; cancelled/blocked/deleted are absent).

### System-directive injection

Use agent.steer() (not agent.inject()): steer wakes the idle driver and starts a turn; inject only
places context until the next step and does not wake an idle agent.

```
import { createUserMessage } from "@deepseek-ai/dsh-llm";
agent.steer(createUserMessage({
  content: [{ type: "text", text: prompt }],
  source: { kind: "user" },
}));
```

The exact prompt = CONTINUATION_PROMPT + the status tail ("[Status: D/T completed, K remaining]" +
the list "- [status] content").

### State and lifecycle

- SessionStateStore: Map\<SessionId, State>; omo fields: countdownTimer/Interval, lastInjectedAt,
  lastIncompleteCount, stagnationCount, consecutiveFailures, abortDetectedAt, wasCancelled,
  tokenLimitDetected, unrecoverableErrorDetected, inFlight, awaitingPostInjectionProgressCheck,
  continuationResponseObserved, continuationBlockReason, pendingUserMessageID, allTodosCompletedAt,
  recentCompactionAt/Epoch, acknowledgedCompactionEpoch.
- TTL of 10 min + prune every 2 min; session.deleted → cleanup().
- dispose()/fiber disposal → cancelAllCountdowns + shutdown.

## 3. Plugin skeleton

### package.json

```
{
  "name": "@deepseek-ai/dsh-boulder",
  "description": "Todo-continuation enforcer: wake idle agents with incomplete todos",
  "version": "0.1.0-rc.6",
  "type": "module",
  "main": "lib/index.js",
  "types": "lib/types/index.d.ts",
  "exports": {
    ".": { "types": "./lib/types/index.d.ts", "default": "./lib/index.js" },
    "./client": "./lib/client.js",
    "./package.json": "./package.json"
  },
  "files": ["lib/index.js", "lib/client.js", "lib/types/**/*.d.ts"],
  "license": "MIT",
  "dsh": { "client": { "inject": [], "platform": "web" } },
  "peerDependencies": {
    "@deepseek-ai/cordis": "^4.0.1",
    "@deepseek-ai/dsh-agent": "^0.1.0-rc.6",
    "@deepseek-ai/dsh-session": "^0.1.0-rc.6",
    "@deepseek-ai/dsh-llm": "^0.1.0-rc.6",
    "@deepseek-ai/dsh-tool-todo": "^0.1.0-rc.6"
  }
}
```

### src/constants.ts (exact text)

```
export const HOOK_NAME = "dsh-boulder";

export const CONTINUATION_PROMPT = [
  "[system-directive todo_continuation]",
  "",
  "Incomplete tasks remain in your todo list. Continue working on the next pending task.",
  "",
  "- Proceed without asking for permission",
  "- Mark each task complete when finished",
  "- Do not stop until all tasks are done",
  "- If you believe all work is already complete, the system is questioning your completion claim. Critically re-examine each todo item from a skeptical perspective, verify the work was actually done correctly, and update the todo list accordingly."
].join(String.fromCharCode(10));

export const COUNTDOWN_SECONDS = 2;
export const TOAST_DURATION_MS = 900;
export const COUNTDOWN_GRACE_PERIOD_MS = 500;
export const ABORT_WINDOW_MS = 3_000;
export const COMPACTION_GUARD_MS = 60_000;
export const CONTINUATION_COOLDOWN_MS = 5_000;
export const MAX_STAGNATION_COUNT = 3;
export const MAX_CONSECUTIVE_FAILURES = 5;
export const FAILURE_RESET_WINDOW_MS = 5 * 60 * 1000;
export const DEFAULT_SKIP_AGENTS = ["compaction", "plan"];
```

The exact CONTINUATION_PROMPT text (rendered, without the JS concatenation):

[system-directive todo_continuation]

Incomplete tasks remain in your todo list. Continue working on the next pending task.

- Proceed without asking for permission
- Mark each task complete when finished
- Do not stop until all tasks are done
- If you believe all work is already complete, the system is questioning your completion claim.
  Critically re-examine each todo item from a skeptical perspective, verify the work was actually
  done correctly, and update the todo list accordingly.

### src/index.ts (host, core logic)

```
import type { Context } from "@deepseek-ai/cordis";
import { createUserMessage } from "@deepseek-ai/dsh-llm";
import type { Agent } from "@deepseek-ai/dsh-agent";
import type { TodoItem } from "@deepseek-ai/dsh-session";
import { CONTINUATION_PROMPT, CONTINUATION_COOLDOWN_MS, ABORT_WINDOW_MS,
  COMPACTION_GUARD_MS, DEFAULT_SKIP_AGENTS, FAILURE_RESET_WINDOW_MS,
  MAX_CONSECUTIVE_FAILURES, MAX_STAGNATION_COUNT } from "./constants";
import { createSessionStateStore } from "./session-state";

interface EnforcerState {
  countdownTimer?: ReturnType<typeof setTimeout>;
  countdownInterval?: ReturnType<typeof setInterval>;
  countdownStartedAt?: number;
  lastInjectedAt?: number;
  lastIncompleteCount?: number;
  stagnationCount: number;
  consecutiveFailures: number;
  inFlight?: boolean;
  wasCancelled?: boolean;
  abortDetectedAt?: number;
  tokenLimitDetected?: boolean;
  unrecoverableErrorDetected?: boolean;
  allTodosCompletedAt?: number;
  recentCompactionAt?: number;
  recentCompactionEpoch?: number;
  acknowledgedCompactionEpoch?: number;
}

export const name = "dsh-boulder";

function readTodos(agent: Agent, ctx: Context): TodoItem[] {
  const snap = (ctx as any).sessionProjections?.snapshot(agent.session).values.todos;
  if (Array.isArray(snap)) return snap as TodoItem[];
  const last = [...agent.session.events].reverse().find(e => e.type === "todo/write");
  return ((last as any)?.data?.todos ?? []) as TodoItem[];
}

function incompleteCount(todos: TodoItem[]): number {
  return todos.filter(t => t.status !== "completed").length;
}

export function apply(ctx: Context, config: Record<string, unknown> = {}) {
  const store = createSessionStateStore();
  const skipAgents: string[] = (config.skipAgents as string[]) ?? DEFAULT_SKIP_AGENTS;

  ctx.on("agent/status", ({ agent, status }) => {
    const sid = agent.session.id as string;
    const st = store.getState(sid);
    if (status === "running") { store.cancelCountdown(sid); return; }
    if (status !== "idle") return;
    void handleIdle(ctx, agent, store, skipAgents);
  });

  ctx.on("agent/pre-step", ({ agent }) => {
    store.cancelCountdown(agent.session.id as string);
  });

  // Replace with the actual compaction event from dsh-compaction.
  ctx.on("session/compacted" as any, (payload: any, next?: () => void) => {
    const sid = payload?.session?.id ?? payload?.sessionId;
    if (!sid) return next?.();
    const st = store.getState(sid as string);
    st.recentCompactionAt = Date.now();
    st.recentCompactionEpoch = (st.recentCompactionEpoch ?? 0) + 1;
    st.acknowledgedCompactionEpoch = undefined;
    return next?.();
  });

  ctx.effect(() => () => store.shutdown(), name + ": shutdown");
}

async function handleIdle(
  ctx: Context, agent: Agent, store: ReturnType<typeof createSessionStateStore>,
  skipAgents: string[],
): Promise<void> {
  const sid = agent.session.id as string;
  const st = store.getState(sid);
  const now = Date.now();

  if (st.allTodosCompletedAt || st.wasCancelled || st.tokenLimitDetected
      || st.unrecoverableErrorDetected || st.inFlight) return;
  if (st.abortDetectedAt && now - st.abortDetectedAt < ABORT_WINDOW_MS) {
    st.abortDetectedAt = undefined; return;
  }

  const todos = readTodos(agent, ctx);
  const incomplete = incompleteCount(todos);
  if (incomplete === 0) {
    st.allTodosCompletedAt = now;
    store.resetContinuationProgress(sid);
    return;
  }

  if (st.recentCompactionAt
      && st.acknowledgedCompactionEpoch !== st.recentCompactionEpoch
      && now - st.recentCompactionAt < COMPACTION_GUARD_MS) return;

  if (skipAgents.some(s => (agent as any).name === s)) return;

  if (st.consecutiveFailures >= MAX_CONSECUTIVE_FAILURES) {
    if (st.lastInjectedAt && now - st.lastInjectedAt >= FAILURE_RESET_WINDOW_MS) {
      st.consecutiveFailures = 0;
    } else return;
  }

  const cooldown = CONTINUATION_COOLDOWN_MS * 2 ** Math.min(st.consecutiveFailures, 5);
  if (st.lastInjectedAt && now - st.lastInjectedAt < cooldown) return;

  const prev = st.lastIncompleteCount;
  if (prev !== undefined && incomplete < prev) st.stagnationCount = 0;
  st.lastIncompleteCount = incomplete;
  if (st.stagnationCount >= MAX_STAGNATION_COUNT) return;

  startCountdown(ctx, agent, incomplete, todos.length);
}

function startCountdown(ctx: Context, agent: Agent, incomplete: number, total: number) {
  const sid = agent.session.id as string;
  const store = (ctx as any).__boulderStore;
  const st = store.getState(sid);
  store.cancelCountdown(sid);

  let seconds = 2;
  st.countdownStartedAt = Date.now();
  emitToast("Resuming in " + seconds + "s... (" + incomplete + " tasks remaining)");
  st.countdownInterval = setInterval(() => {
    seconds -= 1;
    if (seconds > 0) emitToast("Resuming in " + seconds + "s... (" + incomplete + " tasks remaining)");
  }, 1000);

  st.countdownTimer = setTimeout(() => {
    store.cancelCountdown(sid);
    injectContinuation(ctx, agent, incomplete, total);
  }, 2000);
}

async function injectContinuation(
  ctx: Context, agent: Agent, incomplete: number, total: number,
): Promise<void> {
  const sid = agent.session.id as string;
  const store = (ctx as any).__boulderStore;
  const st = store.getState(sid);
  if (st.inFlight || st.wasCancelled || st.tokenLimitDetected
      || st.unrecoverableErrorDetected) return;

  const todos = readTodos(agent, ctx);
  const fresh = incompleteCount(todos);
  if (fresh === 0) { st.allTodosCompletedAt = Date.now(); return; }

  const list = todos.filter(t => t.status !== "completed")
    .map(t => "- [" + t.status + "] " + t.content).join(String.fromCharCode(10));
  const prompt = [CONTINUATION_PROMPT, "",
    "[Status: " + (total - fresh) + "/" + total + " completed, " + fresh + " remaining]",
    "", "Remaining tasks:", list].join(String.fromCharCode(10));

  st.inFlight = true;
  try {
    agent.steer(createUserMessage({
      content: [{ type: "text", text: prompt }],
      source: { kind: "user" },
    }));
    st.inFlight = false;
    st.lastInjectedAt = Date.now();
    st.consecutiveFailures = 0;
  } catch (err) {
    st.inFlight = false;
    st.lastInjectedAt = Date.now();
    st.consecutiveFailures += 1;
    if (isTokenLimit(err)) st.tokenLimitDetected = true;
    if (isUnrecoverable(err)) st.unrecoverableErrorDetected = true;
  }
}

function emitToast(message: string): void {
  (globalThis as any).__boulderToast?.(message);
}
```

Implementation note: in real code the state store lives in the closure of apply and is passed
explicitly (here, for brevity, via ctx.\_\_boulderStore); reading todos goes through
ctx.inject(["sessionProjections"], ...) or a fold of agent.session.events; replace the compaction
event name with the actual one from dsh-compaction. The code is a skeleton of the core logic, not
production.

### src/client.ts (browser)

```
window.__ModuleLoader__.load({
  id: "@deepseek-ai/dsh-boulder/client",
  factory: () => {
    let toastEl: HTMLElement | null = null;
    (window as any).__boulderToast = (message: string) => {
      toastEl?.remove();
      toastEl = document.createElement("div");
      toastEl.textContent = message;
      Object.assign(toastEl.style, {
        position: "fixed", bottom: "16px", right: "16px", zIndex: "9999",
        background: "var(--color-warning, #b45309)", color: "#fff",
        padding: "8px 12px", borderRadius: "8px", fontFamily: "monospace",
      });
      document.body.appendChild(toastEl);
      setTimeout(() => toastEl?.remove(), 900);
    };
  },
});
```

## 4. Risks / open questions

1. 30s vs 5s. The backlog (agent-harness-features.md, agent-guards.md) records "backoff 30s×2", but
   the omo constants.ts has CONTINUATION_COOLDOWN_MS = 5_000 as the exponent base. An explicit owner
   decision is needed: 30s (per the backlog) or 5s (per the omo code).
1. steer vs inject. steer wakes the agent and can be perceived as a new user message; an
   internal-source UserMessage or a dedupe marker is needed so it does not fall into
   "user-interruption" and loop the classification. In omo this is
   createInternalAgentContinuationTextPart + prompt-async-gate; DSH has no analog.
1. skip-agents. The omo list prometheus/compaction/plan does not map 1:1 onto DSH agents; decide
   which DSH roles/subagents to exclude (probably: the compaction agent, the plan-mode agent,
   subagent sessions).
1. Compaction event. In DSH compaction is done by dsh-compaction; the event name and payload
   (session.compacted?) must be confirmed against its types, otherwise the guard will not fire.
1. Pending question. omo uses hasUnansweredQuestion based on messages; in DSH the questions are
   dsh-user-questions / ask_user_question. An exact signal "waiting for a user answer" is needed so
   the agent is not woken on top of a question.
1. State persistence. The omo state lives in the memory of the process. In DSH, restarting the web
   profile loses the counters (stagnation/failures); either accept that or store them in a session
   projection/JSON file.
1. Races and reentrancy. agent/status is an emit; the injection is asynchronous. inFlight is needed
   — cancel the countdown on any running/tool/message event, otherwise double injections are
   possible on fast idle⇄running flips.
1. Tests. Cover on dsh-agent-loop-testkit: idle+incomplete → injection; all skip conditions;
   cooldown/backoff; stagnation 3; compaction-guard 60s; abort-window; token-limit;
   user-interruption.
1. Permissions. Before injecting, check that the agent has edit/write permissions; waking a
   read-only agent is pointless (in omo — hasWritePermission).
1. UI transparency. The 900ms toast in client.ts is a minimum; preferably show the reason ("boulder:
   3 tasks remaining") and give the user a "stop" button (isContinuationStopped).
