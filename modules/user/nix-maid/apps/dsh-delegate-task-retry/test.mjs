#!/usr/bin/env node
/** dsh-delegate-task-retry functional test. */
import { apply } from "./lib/index.js";
let pass = 0, fail = 0;
const ok = (c, n) => { if (c) { pass++; console.log("  ✅ " + n); } else { fail++; console.log("  ❌ " + n); } };
const listeners = {};
apply({ on: (evt, fn) => { listeners[evt] = fn; } });
ok(typeof listeners["agent/pre-step"] === "function", "pre-step listener registered");
const next = async () => ({ kind: "accept", messages: [] });
(async () => {
  // 1. event-shape: failed subagent tool/result → hint
  const msgs1 = [
    { type: "tool/call", callId: "c1", toolName: "subagent", arguments: { prompt: "x" } },
    { type: "tool/result", callId: "c1", toolName: "subagent", isError: true, content: [{ isError: true, text: "boom" }] },
  ];
  const r1 = await listeners["agent/pre-step"]({ agent: { session: { id: "s1" } }, messages: msgs1 }, next);
  ok(r1.messages?.length === 1, "failed subagent → 1 injection");
  ok((r1.messages[0].content?.[0]?.text ?? "").includes("delegate-task-retry"), "marker present");
  // 2. same failure again → dedup (no re-inject)
  const r2 = await listeners["agent/pre-step"]({ agent: { session: { id: "s1" } }, messages: msgs1 }, next);
  ok(r2.messages?.length === 0, "same callId deduped");
  // 3. anthropic block shape: tool_use + tool_result isError
  const msgs3 = [
    { role: "assistant", content: [{ type: "tool_use", id: "t1", name: "subagent_fork", input: { prompt: "y" } }] },
    { role: "user", content: [{ type: "tool_result", tool_use_id: "t1", isError: true, content: "failed" }] },
  ];
  const r3 = await listeners["agent/pre-step"]({ agent: { session: { id: "s2" } }, messages: msgs3 }, next);
  ok(r3.messages?.length === 1, "block-shape failure → 1 injection");
  // 4. successful delegation → untouched
  const msgs4 = [
    { type: "tool/call", callId: "c2", toolName: "subagent", arguments: {} },
    { type: "tool/result", callId: "c2", toolName: "subagent", content: [{ type: "text", text: "ok" }] },
  ];
  const r4 = await listeners["agent/pre-step"]({ agent: { session: { id: "s3" } }, messages: msgs4 }, next);
  ok(r4.messages?.length === 0, "successful delegation untouched");
  // 5. non-delegation error → untouched
  const msgs5 = [
    { type: "tool/call", callId: "c3", toolName: "bash", arguments: {} },
    { type: "tool/result", callId: "c3", toolName: "bash", isError: true, content: [{ isError: true }] },
  ];
  const r5 = await listeners["agent/pre-step"]({ agent: { session: { id: "s4" } }, messages: msgs5 }, next);
  ok(r5.messages?.length === 0, "non-delegation error untouched");
  console.log("\n" + pass + " passed, " + fail + " failed");
  process.exit(fail === 0 ? 0 : 1);
})();
