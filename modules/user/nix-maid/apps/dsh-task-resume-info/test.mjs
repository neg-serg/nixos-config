#!/usr/bin/env node
/** dsh-task-resume-info functional test. */
import { apply } from "./lib/index.js";
let pass = 0, fail = 0;
const ok = (c, n) => { if (c) { pass++; console.log("  ✅ " + n); } else { fail++; console.log("  ❌ " + n); } };
const listeners = {};
apply({ on: (evt, fn) => { listeners[evt] = fn; } });
ok(typeof listeners["session/event"] === "function", "session/event listener registered");
ok(typeof listeners["agent/pre-step"] === "function", "pre-step listener registered");
const next = async () => ({ kind: "accept", messages: [] });

function fakeSession(id, events) {
  return { id, events };
}
function todoEvent(todos) { return { type: "todo/write", data: { todos } }; }
function userMsg(text) { return { type: "assistant/message", data: { message: { role: "user", content: [{ type: "text", text }] } } }; }

(async () => {
  // 1. reseed marks session
  const s = fakeSession("s1", [todoEvent([{ content: "A", status: "pending" }, { content: "B", status: "completed" }]), userMsg("сделай A")]);
  listeners["session/event"](s, { type: "session/end-seed", data: {} });
  // 2. first pre-step injects resume context
  const r1 = await listeners["agent/pre-step"]({ agent: { session: s }, messages: [] }, next);
  ok(r1.messages?.length === 1, "resume context injected once");
  const t = r1.messages[0].content?.[0]?.text ?? "";
  ok(t.includes("task-resume-info"), "marker present");
  ok(t.includes("- [ ] A"), "pending todo listed");
  ok(!t.includes("- [ ] B"), "completed todo omitted");
  ok(t.includes("сделай A"), "last user ask included");
  // 3. second pre-step → no duplicate
  const r2 = await listeners["agent/pre-step"]({ agent: { session: s }, messages: [] }, next);
  ok(r2.messages?.length === 0, "no duplicate on next step");
  // 4. no reseed → untouched
  const s2 = fakeSession("s2", [userMsg("hi")]);
  const r3 = await listeners["agent/pre-step"]({ agent: { session: s2 }, messages: [] }, next);
  ok(r3.messages?.length === 0, "non-reseeded session untouched");
  // 5. reseed without todos/asks → no injection
  const s3 = fakeSession("s3", []);
  listeners["session/event"](s3, { type: "session/end-seed", data: {} });
  const r4 = await listeners["agent/pre-step"]({ agent: { session: s3 }, messages: [] }, next);
  ok(r4.messages?.length === 0, "empty context → no injection");
  console.log("\n" + pass + " passed, " + fail + " failed");
  process.exit(fail === 0 ? 0 : 1);
})();
