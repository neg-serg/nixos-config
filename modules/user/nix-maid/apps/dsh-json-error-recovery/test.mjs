#!/usr/bin/env node
/**
 * dsh-json-error-recovery functional test.
 * Usage: node test.mjs
 * Verifies: plugin registers; a failed edit in the last messages triggers
 * exactly one corrective injection per session; success path stays untouched.
 */
import { apply } from "./lib/index.js";

let pass = 0, fail = 0;
const ok = (c, n) => { if (c) { pass++; console.log("  ✅ " + n); } else { fail++; console.log("  ❌ " + n); } };

// minimal ctx: only the event registration we use
const listeners = {};
const ctx = { on: (evt, fn) => { listeners[evt] = fn; } };
apply(ctx);
ok(typeof listeners["agent/pre-step"] === "function", "agent/pre-step listener registered");

const next = async () => ({ kind: "accept", messages: [] });

(async () => {
  // 1. failed edit (error field) → injection
  const bad = await listeners["agent/pre-step"]({ agent: { session: { id: "s1" } }, messages: [{ toolName: "edit", error: "old_string not found" }] }, next);
  ok(bad.messages?.length === 1, "error edit → 1 injection");
  ok((bad.messages[0].content?.[0]?.text ?? "").includes("json-error-recovery"), "injection has marker");
  ok((bad.messages[0].content?.[0]?.text ?? "").includes("old_string"), "injection mentions old_string");

  // 2. same session again → capped (MAX_PER_SESSION=3): allow up to 3
  let c = 1;
  for (let i = 0; i < 5; i++) {
    const r = await listeners["agent/pre-step"]({ agent: { session: { id: "s1" } }, messages: [{ toolName: "edit", error: "hash mismatch" }] }, next);
    if (r.messages?.length === 1) c++;
  }
  ok(c <= 3, "session cap respected (fired " + c + " ≤ 3)");

  // 3. success path → untouched
  const okRes = await listeners["agent/pre-step"]({ agent: { session: { id: "s2" } }, messages: [{ toolName: "edit", result: "ok" }] }, next);
  ok(okRes.messages?.length === 0, "successful edit → no injection");

  // 4. non-target tool error → untouched
  const other = await listeners["agent/pre-step"]({ agent: { session: { id: "s3" } }, messages: [{ toolName: "bash", error: "boom" }] }, next);
  ok(other.messages?.length === 0, "non-target tool error → no injection");

  console.log("\n" + pass + " passed, " + fail + " failed");
  process.exit(fail === 0 ? 0 : 1);
})();
