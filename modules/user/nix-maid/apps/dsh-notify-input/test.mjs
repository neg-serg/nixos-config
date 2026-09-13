#!/usr/bin/env node
/**
 * dsh-notify-input plugin functional test.
 *
 * The plugin is plumbing: watch the two host request events that block a turn,
 * wait out a grace period, and put an OSC notification on stdout when the
 * request is still unresolved. What the assertions pin is that contract — the
 * protocol table, the gates (prefs / env / TTY), the copy, and above all that an
 * auto-approved request stays silent while a card waiting on a human does not,
 * and that a failure in this listener can never disturb the request path.
 *
 * Usage: node test.mjs
 */
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { apply, approvalNotice, detectProtocol, envAllows, inject, name, notifySequence, parseNotifyPref, questionNotice, sanitize } from "./lib/index.js";

/** A real prefs file, so the /config notify off gate is exercised end to end. */
function prefsFile(contents) {
  const dir = mkdtempSync(join(tmpdir(), "dsh-notify-input-"));
  const path = join(dir, "prefs.json");
  writeFileSync(path, contents);
  return path;
}

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
const eq = (actual, expected, label) => ok(actual === expected, `${label} (${JSON.stringify(actual)})`);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** process.env is a global the plugin reads; swap it for one case and restore. */
async function withEnv(overrides, fn) {
  const saved = { ...process.env };
  for (const key of Object.keys(process.env)) delete process.env[key];
  Object.assign(process.env, overrides);
  try {
    return await fn();
  } finally {
    for (const key of Object.keys(process.env)) delete process.env[key];
    Object.assign(process.env, saved);
  }
}

/**
 * Fake ctx + fake stdout. Keeps the raw listener and its options so the test can
 * drive the waterfall itself (and assert `prepend`).
 */
function harness({ graceMs = 20, prefsPath = null, isTTY = true, writeThrows = false } = {}) {
  const writes = [];
  const listeners = {};
  const disposers = [];
  const stdout = {
    isTTY,
    write: (chunk) => {
      if (writeThrows) throw new Error("EPIPE");
      writes.push(chunk);
      return true;
    },
  };
  const ctx = {
    on: (event, listener, options) => {
      listeners[event] = { listener, options };
      const dispose = () => {
        delete listeners[event];
        return true;
      };
      disposers.push(dispose);
      return dispose;
    },
    effect: (fn) => {
      disposers.push(fn());
    },
  };
  apply(ctx, { graceMs, prefsPath, stdout });
  return {
    writes,
    listeners,
    stdout,
    disposeAll: () => {
      for (const dispose of disposers) {
        try {
          dispose();
        } catch {
          /* already disposed */
        }
      }
    },
  };
}

const KITTY_ENV = { KITTY_WINDOW_ID: "1", TERM: "xterm-kitty" };
const APPROVAL = { toolName: "bash", reason: "rm -rf build", agent: { session: { id: "s1" } } };
const QUESTION = { questions: [{ id: "q1", question: "Какой пресет применить?", header: "Выбор" }] };

console.log("sanitize");
eq(name, "dsh-notify-input", "plugin name matches the patch row");
ok(Array.isArray(inject) && inject.length === 0, "declares no hard service dependency");
eq(sanitize("  a\n\nb  ", 40), "a b", "collapses whitespace");
eq(sanitize("x\u001b]9;evil\u0007", 40), "x ]9;evil", "clamps control characters to spaces");
eq(sanitize("abcdef", 3), "abc", "applies the limit");
eq(sanitize(undefined, 10), "", "undefined becomes empty");

console.log("detectProtocol");
eq(detectProtocol({ KITTY_WINDOW_ID: "5", TERM: "xterm-256color" }), "kitty", "KITTY_WINDOW_ID wins");
eq(detectProtocol({ TERM: "xterm-kitty" }), "kitty", "TERM containing kitty");
eq(detectProtocol({ TERM_PROGRAM: "iTerm.app" }), "osc9", "iTerm2");
eq(detectProtocol({ TERM_PROGRAM: "WezTerm" }), "osc9", "WezTerm");
eq(detectProtocol({ TERM_PROGRAM: "ghostty" }), "osc9", "Ghostty via TERM_PROGRAM");
eq(detectProtocol({ TERM: "xterm-ghostty" }), "osc9", "Ghostty via TERM");
eq(detectProtocol({ TERM: "xterm", DSH_NOTIFY_OSC: "0" }), null, "DSH_NOTIFY_OSC=0 forces off");
eq(detectProtocol({ TERM: "xterm", DSH_NOTIFY_OSC: "1" }), "osc9", "DSH_NOTIFY_OSC=1 forces OSC 9");
eq(detectProtocol({ TERM: "xterm", KITTY_WINDOW_ID: "1", DSH_NOTIFY_OSC: "0" }), null, "kill switch beats detection");
eq(detectProtocol({ TERM: "xterm" }), null, "unknown terminal stays silent");

console.log("notifySequence");
eq(notifySequence("osc9", "t", "b"), "\u001b]9;t — b\u0007", "OSC 9 is BEL-terminated");
eq(notifySequence("kitty", "t", "b"), "\u001b]99;;t — b\u001b\\", "kitty OSC 99 is ST-terminated");
eq(notifySequence("osc9", "only", ""), "\u001b]9;only\u0007", "title only");
eq(notifySequence("osc9", "", "only"), "\u001b]9;only\u0007", "body only");
eq(notifySequence("osc9", "", ""), null, "empty payload yields no sequence");
ok(!notifySequence("osc9", "a\u001b]9;x", "b").includes("\u001b]9;x"), "payload cannot inject a sequence");

console.log("parseNotifyPref");
eq(parseNotifyPref(JSON.stringify({ notifyOs: false })), false, "notifyOs false disables");
eq(parseNotifyPref(JSON.stringify({ notifyOs: true })), true, "notifyOs true enables");
eq(parseNotifyPref(JSON.stringify({ theme: "custom:neg" })), true, "absent notifyOs enables");
eq(parseNotifyPref("{ not json"), true, "broken JSON defaults to enabled");
eq(parseNotifyPref("[]"), true, "non-object defaults to enabled");

console.log("envAllows");
eq(envAllows({}), true, "clean environment allows");
eq(envAllows({ DSH_NOTIFY_INPUT: "0" }), false, "DSH_NOTIFY_INPUT=0");
eq(envAllows({ DSH_TUI_SKIP_NOTIFY: "1" }), false, "DSH_TUI_SKIP_NOTIFY=1");
eq(envAllows({ VITEST: "1" }), false, "VITEST=1");
eq(envAllows({ CI: "true" }), false, "CI=true");

console.log("copy");
eq(approvalNotice(APPROVAL).title, "dsh · Нужно подтверждение", "approval title");
eq(approvalNotice(APPROVAL).body, "bash — rm -rf build", "approval body carries tool and reason");
eq(approvalNotice({ toolName: "bash" }).body, "bash", "approval body without reason");
eq(approvalNotice({ reason: "why" }), null, "approval without tool name is dropped");
eq(questionNotice(QUESTION).title, "dsh · Агент ждёт ответа", "question title");
eq(questionNotice(QUESTION).body, "Какой пресет применить?", "question body");
eq(questionNotice({ questions: [{ id: "q", header: "Только заголовок" }] }).body, "Только заголовок", "header fallback");
eq(questionNotice({ questions: [] }), null, "empty question list is dropped");
eq(questionNotice({}), null, "missing questions is dropped");

console.log("registration");
{
  const h = harness();
  ok(h.listeners["approval/request"] !== undefined, "listens on approval/request");
  ok(h.listeners["user-questions/request"] !== undefined, "listens on user-questions/request");
  eq(h.listeners["approval/request"].options.prepend, true, "approval listener is prepended");
  eq(h.listeners["user-questions/request"].options.prepend, true, "question listener is prepended");
  eq(h.listeners["approval/request"].options.global, true, "approval listener bypasses the context filter");
  eq(h.listeners["user-questions/request"].options.global, true, "question listener bypasses the context filter");
  h.disposeAll();
}

console.log("auto-approved request stays silent");
await withEnv(KITTY_ENV, async () => {
  const h = harness();
  const returned = h.listeners["approval/request"].listener(APPROVAL, () => Promise.resolve("allowed-once"));
  ok(returned instanceof Promise, "next() result is returned to the waterfall");
  await sleep(60);
  eq(h.writes.length, 0, "no notification when the request settles immediately");
  h.disposeAll();
});

console.log("pending request notifies");
await withEnv(KITTY_ENV, async () => {
  const h = harness();
  let settle;
  const pending = new Promise((resolve) => {
    settle = resolve;
  });
  h.listeners["approval/request"].listener(APPROVAL, () => pending);
  await sleep(10);
  eq(h.writes.length, 0, "nothing before the grace elapses");
  await sleep(40);
  eq(h.writes.length, 1, "one notification while the card is up");
  ok(h.writes[0].includes("Нужно подтверждение"), "title reaches the terminal");
  ok(h.writes[0].includes("bash — rm -rf build"), "body reaches the terminal");
  ok(h.writes[0].startsWith("\u001b]99;;"), "kitty protocol is used");
  settle("allowed-once");
  await sleep(40);
  eq(h.writes.length, 1, "answering does not re-notify");
  h.disposeAll();
});

console.log("question notifies, answering before the grace does not");
await withEnv(KITTY_ENV, async () => {
  const h = harness();
  h.listeners["user-questions/request"].listener(QUESTION, () => Promise.resolve({ answers: [] }));
  await sleep(60);
  eq(h.writes.length, 0, "answered within the grace stays silent");
  h.disposeAll();
});
await withEnv(KITTY_ENV, async () => {
  const h = harness();
  h.listeners["user-questions/request"].listener(QUESTION, () => new Promise(() => {}));
  await sleep(60);
  eq(h.writes.length, 1, "unanswered question notifies");
  ok(h.writes[0].includes("Агент ждёт ответа"), "question title reaches the terminal");
  ok(h.writes[0].includes("Какой пресет применить?"), "question text reaches the terminal");
  h.disposeAll();
});

console.log("non-waterfall emit");
await withEnv(KITTY_ENV, async () => {
  const h = harness();
  eq(h.listeners["approval/request"].listener(APPROVAL, undefined), undefined, "no next() returns undefined");
  await sleep(60);
  eq(h.writes.length, 1, "a plain emit still notifies");
  h.disposeAll();
});

console.log("gates");
await withEnv({ ...KITTY_ENV, DSH_NOTIFY_INPUT: "0" }, async () => {
  const h = harness();
  h.listeners["approval/request"].listener(APPROVAL, () => new Promise(() => {}));
  await sleep(60);
  eq(h.writes.length, 0, "DSH_NOTIFY_INPUT=0 silences the plugin");
  h.disposeAll();
});
await withEnv({ TERM: "xterm" }, async () => {
  const h = harness();
  h.listeners["approval/request"].listener(APPROVAL, () => new Promise(() => {}));
  await sleep(60);
  eq(h.writes.length, 0, "unrecognised terminal writes nothing");
  h.disposeAll();
});
await withEnv(KITTY_ENV, async () => {
  const h = harness({ isTTY: false });
  h.listeners["approval/request"].listener(APPROVAL, () => new Promise(() => {}));
  await sleep(60);
  eq(h.writes.length, 0, "a non-TTY stdout (piped session) writes nothing");
  h.disposeAll();
});
await withEnv(KITTY_ENV, async () => {
  const h = harness({ prefsPath: "/nonexistent/dsh-tui-prefs.json" });
  h.listeners["approval/request"].listener(APPROVAL, () => new Promise(() => {}));
  await sleep(60);
  eq(h.writes.length, 1, "missing prefs file defaults to enabled");
  h.disposeAll();
});
await withEnv(KITTY_ENV, async () => {
  const h = harness({ prefsPath: prefsFile(JSON.stringify({ theme: "custom:neg", notifyOs: false })) });
  h.listeners["approval/request"].listener(APPROVAL, () => new Promise(() => {}));
  await sleep(60);
  eq(h.writes.length, 0, "prefs notifyOs=false (the /config notify off switch) silences it");
  h.disposeAll();
});
await withEnv(KITTY_ENV, async () => {
  const h = harness({ prefsPath: prefsFile("{ broken") });
  h.listeners["approval/request"].listener(APPROVAL, () => new Promise(() => {}));
  await sleep(60);
  eq(h.writes.length, 1, "a corrupt prefs file does not silence it");
  h.disposeAll();
});

console.log("robustness");
await withEnv(KITTY_ENV, async () => {
  const h = harness();
  let thrown = null;
  try {
    h.listeners["approval/request"].listener(APPROVAL, () => {
      throw new Error("downstream failed");
    });
  } catch (error) {
    thrown = error;
  }
  ok(thrown !== null && thrown.message === "downstream failed", "a throwing next() propagates");
  await sleep(60);
  eq(h.writes.length, 0, "the grace timer is disarmed when the waterfall throws");
  h.disposeAll();
});
await withEnv(KITTY_ENV, async () => {
  const h = harness({ writeThrows: true });
  h.listeners["approval/request"].listener(APPROVAL, () => new Promise(() => {}));
  await sleep(60);
  ok(true, "a write failure is swallowed, not thrown");
  h.disposeAll();
});
await withEnv(KITTY_ENV, async () => {
  const h = harness();
  h.listeners["approval/request"].listener(APPROVAL, () => new Promise(() => {}));
  h.disposeAll();
  await sleep(60);
  eq(h.writes.length, 0, "unloading clears the armed timer");
});

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
