#!/usr/bin/env node
/**
 * dsh-worktree plugin functional test.
 *
 * Drives the registered `/worktree` handler against a fake Cordis context: a
 * recording command registry and a recording subprocess seam. The assertions
 * that matter are the ones a real session would break on — verb validation
 * (a typo must not reach the helper), cwd taken from the session, and the
 * DSH_WORKTREE_* forwarding that the subprocess env scrub would otherwise eat.
 */
import { apply, inject, name } from "./lib/index.js";

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

/** Fake ctx: captures the handler and records every spawn. */
function harness({ resolve, resolveThrows, spawnThrows, exitCode = 0, signal = null, doneRejects, stdout = "", stderr = "" } = {}) {
  const spawns = [];
  let def;
  const ctx = {
    commands: { register: (d) => { def = d; } },
    subprocess: {
      resolveExecutable: async () => {
        if (resolveThrows) throw new Error("not found");
        return resolve ?? "/nix/store/fake-dsh-worktree";
      },
      spawn: (spec) => {
        spawns.push(spec);
        if (spawnThrows) throw new Error("spawn blew up");
        return {
          done: doneRejects ? Promise.reject(new Error("provider failure")) : Promise.resolve({ exitCode, signal }),
          collected: {
            stdout: { readFrom: () => ({ text: stdout, nextOffset: stdout.length, lossy: false }) },
            stderr: { readFrom: () => ({ text: stderr, nextOffset: stderr.length, lossy: false }) },
          },
        };
      },
    },
  };
  apply(ctx);
  return { def, handler: def?.handler, spawns };
}

const call = (handler, rawInput, agent) => handler({ rawInput, agent });

ok(name === "dsh-worktree", "plugin name matches the package/patch row");
ok(inject.includes("commands") && inject.includes("subprocess"), "injects commands + subprocess");
{
  const { def, handler } = harness();
  ok(typeof handler === "function", "registers a command handler");
  ok(def?.name === "worktree", "the command is named 'worktree'");
  ok(typeof def?.description === "string" && def.description !== "", "the command carries a description");
}

// ── argv handling ────────────────────────────────────────────────────────────
{
  const { handler, spawns } = harness();
  const r = await call(handler, "", undefined);
  ok(spawns.length === 1 && spawns[0].argv.slice(1).join(" ") === "list", "empty input runs 'list'");
  ok(r.kind === "success", "empty input succeeds");
}
{
  const { handler, spawns } = harness();
  await call(handler, "new task1 --open print", undefined);
  ok(
    spawns[0].argv.slice(1).join(" ") === "new task1 --open print",
    "arguments are forwarded verbatim"
  );
}
{
  const { handler, spawns } = harness();
  const r = await call(handler, "destroy /", undefined);
  ok(spawns.length === 0, "an unknown verb never reaches the helper");
  ok(r.kind === "error" && r.text.includes("usage:"), "an unknown verb returns the usage");
}
{
  const { handler } = harness();
  const r = await call(handler, "new task1 --force; rm -rf /", undefined);
  ok(r.kind === "success", "known verb with odd arguments is passed through (no shell is involved)");
}

// ── cwd + executable resolution ──────────────────────────────────────────────
{
  const { handler, spawns } = harness();
  await call(handler, "list", { session: { header: { cwd: "/repo/worktree-a" } } });
  ok(spawns[0].cwd === "/repo/worktree-a", "cwd comes from the session header");
}
{
  const { handler, spawns } = harness();
  await call(handler, "list", undefined);
  ok(spawns[0].cwd === process.cwd(), "cwd falls back to the harness process");
}
{
  const { handler, spawns } = harness({ resolve: "/home/neg/.local/bin/dsh-worktree" });
  await call(handler, "list", undefined);
  ok(spawns[0].argv[0] === "/home/neg/.local/bin/dsh-worktree", "a resolved executable path is used");
}
{
  const { handler, spawns } = harness({ resolveThrows: true });
  await call(handler, "list", undefined);
  ok(spawns[0].argv[0] === "dsh-worktree", "resolution failure falls back to a PATH lookup");
}

// ── env forwarding (the subprocess seam scrubs DSH_*) ────────────────────────
{
  const saved = { ...process.env };
  process.env.DSH_WORKTREE_ROOT = "/tmp/trees";
  process.env.DSH_WORKTREE_CMD = "dsh --profile tui";
  process.env.DSH_SOMETHING_ELSE = "must-not-leak";
  const { handler, spawns } = harness();
  await call(handler, "list", undefined);
  ok(spawns[0].env.DSH_WORKTREE_ROOT === "/tmp/trees", "DSH_WORKTREE_ROOT is forwarded explicitly");
  ok(spawns[0].env.DSH_WORKTREE_CMD === "dsh --profile tui", "DSH_WORKTREE_CMD is forwarded explicitly");
  ok(spawns[0].env.DSH_SOMETHING_ELSE === undefined, "unrelated DSH_* names are not forwarded");
  process.env = saved;
}
{
  const saved = { ...process.env };
  delete process.env.DSH_WORKTREE_ROOT;
  const { handler, spawns } = harness();
  await call(handler, "list", undefined);
  ok(spawns[0].env.DSH_WORKTREE_ROOT === undefined, "an unset variable is not forwarded as undefined");
  process.env = saved;
}

// ── result rendering ─────────────────────────────────────────────────────────
{
  const { handler } = harness({ exitCode: 0, stdout: "/tmp/trees/repo/task1\n", stderr: "creating...\n" });
  const r = await call(handler, "new task1", undefined);
  ok(r.kind === "success", "exit 0 → success");
  ok(r.text.includes("/tmp/trees/repo/task1"), "stdout reaches the reply");
  ok(r.text.includes("creating..."), "stderr reaches the reply");
}
{
  const { handler } = harness({ exitCode: 0 });
  const r = await call(handler, "prune", undefined);
  ok(r.kind === "success" && r.text === "готово", "exit 0 with no output → a short confirmation");
}
{
  const { handler } = harness({ exitCode: 2, stderr: "dsh-worktree: already exists" });
  const r = await call(handler, "new task1", undefined);
  ok(r.kind === "error", "non-zero exit → error");
  ok(r.text.includes("already exists"), "the helper's message is surfaced");
}
{
  const { handler } = harness({ exitCode: 3 });
  const r = await call(handler, "list", undefined);
  ok(r.kind === "error" && r.text.includes("3"), "a silent failure still reports the exit code");
}
{
  const { handler } = harness({ exitCode: null, signal: "SIGTERM" });
  const r = await call(handler, "list", undefined);
  ok(r.kind === "error" && r.text.includes("SIGTERM"), "a signal death is reported");
}
{
  const { handler } = harness({ spawnThrows: true });
  const r = await call(handler, "list", undefined);
  ok(r.kind === "error" && r.text.includes(".local/bin"), "a spawn failure points at PATH");
}
{
  const { handler } = harness({ doneRejects: true });
  const r = await call(handler, "list", undefined);
  ok(r.kind === "error" && r.text.includes("120"), "a rejected outcome reports the timeout window");
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
