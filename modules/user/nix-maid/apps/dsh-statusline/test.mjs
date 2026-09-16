#!/usr/bin/env node
/**
 * dsh-statusline plugin functional test.
 *
 * The plugin is plumbing: gather session state → run the status-line script with
 * the payload on stdin → put its first stdout line in the terminal title. What
 * the assertions pin is the plumbing's steady-state contract — the payload shape
 * the script receives, the OSC 1/2 encoding, the gates, the throttle, and that a
 * failing or missing script can never disturb the session.
 */
import { apply, inject, name, titleSequence } from "./lib/index.js";

let pass = 0;
let fail = 0;
const ok = (cond, label) => {
  if (cond) {
    pass += 1;
    console.log("  ✅ " + label);
  } else {
    fail += 1;
    console.log("  ❌ " + label);
  }
};

const SESSION = { id: "s1", header: { cwd: "/repo/wt-x" } };

/** Fake ctx + fake stdout the plugin writes escape sequences into. */
function harness({ output = "⎇ main ◆1\n", exitCode = 0, resolveThrows = false, spawnThrows = false, intervalMs = 0, command } = {}) {
  const spawns = [];
  const writes = [];
  const listeners = {};
  const resolved = [];
  const realStdout = process.stdout;
  const fakeStdout = { isTTY: true, write: (chunk) => { writes.push(chunk); return true; } };
  const ctx = {
    on: (event, fn) => { listeners[event] = fn; },
    effect: () => {},
    subprocess: {
      resolveExecutable: async (asked) => {
        resolved.push(asked);
        if (resolveThrows) throw new Error("not found");
        return "/home/neg/.local/bin/dsh-statusline";
      },
      spawn: (spec) => {
        spawns.push(spec);
        if (spawnThrows) throw new Error("spawn failed");
        return {
          done: Promise.resolve({ exitCode, signal: null }),
          collected: { stdout: { readFrom: () => ({ text: output, nextOffset: output.length, lossy: false }) } },
        };
      },
    },
  };
  apply(ctx, command === undefined ? { intervalMs } : { intervalMs, command });
  const emit = (session, event) => listeners["session/event"](session, event);
  const status = (payload) => listeners["agent/status"](payload);
  return { spawns, writes, emit, status, listeners, resolved, realStdout, fakeStdout };
}

/** Run a refresh with process.stdout swapped for a capturing stub. */
async function captured(fn, harnessInstance) {
  const real = Object.getOwnPropertyDescriptor(process, "stdout");
  Object.defineProperty(process, "stdout", { value: harnessInstance.fakeStdout, configurable: true });
  try {
    await fn();
    // The listener fires the refresh without awaiting it, so the stub must
    // outlive the microtask/timer that actually writes the title.
    await new Promise((resolve) => setTimeout(resolve, 20));
  } finally {
    Object.defineProperty(process, "stdout", real);
  }
}

ok(name === "dsh-statusline", "plugin name matches the package/patch row");
ok(inject.includes("subprocess"), "injects the subprocess seam");
{
  const h = harness();
  ok(typeof h.listeners["session/event"] === "function", "listens for session events");
  ok(typeof h.listeners["agent/status"] === "function", "listens for agent status");
  ok(h.listeners["session/event"].length === 2, "the session listener takes (session, event)");
}
ok(titleSequence("x") === "\u001b]2;x\u0007\u001b]1;x\u0007", "the title sequence sets OSC 2 and OSC 1");

// ── the happy path: state → script → title ───────────────────────────────────
{
  const h = harness();
  h.emit(SESSION, { type: "assistant/message", data: { turn: 4, usage: { inputTokens: 515, cacheReadTokens: 1024 } } });
  await captured(() => h.emit(SESSION, { type: "turn/end", data: { turn: 4, reason: { kind: "completed" } } }), h);
  ok(h.spawns.length === 1, "a finished turn runs the status-line command once");
  ok(h.spawns[0].argv[0] === "/home/neg/.local/bin/dsh-statusline", "the resolved helper is used");
  ok(h.spawns[0].cwd === "/repo/wt-x", "the script runs in the session cwd");

  const sent = JSON.parse(h.spawns[0].stdio.stdin.data);
  ok(sent.session_id === "s1", "the payload carries the session id");
  ok(sent.turn === 4, "the payload carries the turn number");
  ok(sent.workspace.current_dir === "/repo/wt-x", "the payload carries the workspace directory");
  ok(sent.context.estimated_tokens === 1539, "context tokens = input + cache-read (the input-side definition)");
  ok(h.spawns[0].stdio.stdin.data !== undefined, "the payload arrives on stdin (the protocol shape)");

  ok(h.writes.length === 1, "exactly one title write");
  ok(h.writes[0] === titleSequence("⎇ main ◆1"), "the script's first line becomes the title");
}
{
  const h = harness({ output: "line one\nline two\n" });
  await captured(() => h.emit(SESSION, { type: "turn/end", data: { turn: 1 } }), h);
  ok(h.writes[0].includes("line one") && !h.writes[0].includes("line two"), "only the first stdout line is used");
}
{
  const h = harness({ output: "same" });
  await captured(() => h.emit(SESSION, { type: "turn/end", data: { turn: 1 } }), h);
  await captured(() => h.emit(SESSION, { type: "turn/end", data: { turn: 2 } }), h);
  ok(h.spawns.length === 2 && h.writes.length === 1, "an unchanged title is not written twice");
}
{
  const h = harness({ output: "ok\u001b]2;evil\u0007" });
  await captured(() => h.emit(SESSION, { type: "turn/end", data: { turn: 1 } }), h);
  ok(!h.writes[0].includes("\u001b]2;evil"), "a control character from the script cannot open a sequence");
  ok(h.writes[0].split("\u001b").length === 3, "exactly the two OSC introducers remain");
}

// ── gates ────────────────────────────────────────────────────────────────────
{
  const h = harness({ output: "" });
  await captured(() => h.emit(SESSION, { type: "turn/end", data: { turn: 1 } }), h);
  ok(h.writes.length === 0, "an empty script output leaves the title alone");
}
{
  const h = harness({ exitCode: 1 });
  await captured(() => h.emit(SESSION, { type: "turn/end", data: { turn: 1 } }), h);
  ok(h.writes.length === 0, "a failing script leaves the title alone");
}
{
  const h = harness({ resolveThrows: true });
  await captured(() => h.emit(SESSION, { type: "turn/end", data: { turn: 1 } }), h);
  ok(h.spawns.length === 0 && h.writes.length === 0, "a missing helper is skipped silently");
}
{
  const h = harness({ spawnThrows: true });
  await captured(() => h.emit(SESSION, { type: "turn/end", data: { turn: 1 } }), h);
  ok(h.writes.length === 0, "a spawn failure never disturbs the session");
}
{
  const saved = process.env.DSH_STATUSLINE;
  process.env.DSH_STATUSLINE = "0";
  const h = harness();
  await captured(() => h.emit(SESSION, { type: "turn/end", data: { turn: 1 } }), h);
  ok(h.spawns.length === 0, "DSH_STATUSLINE=0 disables it");
  if (saved === undefined) delete process.env.DSH_STATUSLINE;
  else process.env.DSH_STATUSLINE = saved;
}
{
  const real = Object.getOwnPropertyDescriptor(process, "stdout");
  Object.defineProperty(process, "stdout", { value: { isTTY: false, write: () => true }, configurable: true });
  const h = harness();
  try {
    h.emit(SESSION, { type: "turn/end", data: { turn: 1 } });
    await new Promise((r) => setTimeout(r, 5));
  } finally {
    Object.defineProperty(process, "stdout", real);
  }
  ok(h.spawns.length === 0, "a non-TTY stdout is never written to");
}
{
  // A TUI bundle patch's frame renderer would own the status line when present.
  globalThis.__dshTuiStatusLineFrame = true;
  const h = harness();
  await captured(() => h.emit(SESSION, { type: "turn/end", data: { turn: 1 } }), h);
  ok(h.spawns.length === 0, "the plugin stands down while the frame renders the status line");
  process.env.DSH_STATUSLINE_TARGET = "title";
  const h2 = harness();
  await captured(() => h2.emit(SESSION, { type: "turn/end", data: { turn: 1 } }), h2);
  ok(h2.spawns.length === 1, "DSH_STATUSLINE_TARGET=title overrides the handshake");
  delete process.env.DSH_STATUSLINE_TARGET;
  delete globalThis.__dshTuiStatusLineFrame;
}
{
  const h = harness({ intervalMs: 60_000 });
  await captured(() => h.emit(SESSION, { type: "turn/end", data: { turn: 1 } }), h);
  await captured(() => h.emit(SESSION, { type: "turn/end", data: { turn: 2 } }), h);
  ok(h.spawns.length === 1, "the throttle keeps it to one run per interval");
}
{
  const h = harness({ output: "idle" });
  await captured(() => h.status({ agent: { session: SESSION }, status: "idle" }), h);
  ok(h.spawns.length === 1, "going idle also refreshes the title");
  await captured(() => h.status({ agent: { session: SESSION }, status: "running" }), h);
  ok(h.spawns.length === 1, "a running status does not refresh");
}
{
  const h = harness();
  await captured(() => h.emit(SESSION, { type: "unknown/event", data: {} }), h);
  ok(h.spawns.length === 0, "unrelated events are ignored");
}
{
  const h = harness({ command: "/tmp/my-status.sh" });
  await captured(() => h.emit(SESSION, { type: "turn/end", data: { turn: 1 } }), h);
  ok(h.resolved[0] === "/tmp/my-status.sh", "a configured command replaces the default helper");
  ok(h.spawns.length === 1, "the configured command still goes through the provider lookup");
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
