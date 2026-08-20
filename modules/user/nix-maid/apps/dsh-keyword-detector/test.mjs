#!/usr/bin/env node
/** dsh-keyword-detector functional test. */
import { apply } from "./lib/index.js";
let pass = 0, fail = 0;
const ok = (c, n) => { if (c) { pass++; console.log("  ✅ " + n); } else { fail++; console.log("  ❌ " + n); } };
const listeners = {};
apply({ on: (evt, fn) => { listeners[evt] = fn; } });
ok(typeof listeners["agent/pre-step"] === "function", "pre-step listener registered");
const next = async () => ({ kind: "accept", messages: [] });
(async () => {
  // 1. "отвечай коротко" → hint injected
  const r1 = await listeners["agent/pre-step"]({ agent: { session: { id: "s1" } }, messages: [{ role: "user", content: "Сделай, но коротко" }] }, next);
  ok(r1.messages?.length === 1, "keyword short → 1 injection");
  ok((r1.messages[0].content?.[0]?.text ?? "").includes("коротко"), "hint mentions short");
  ok((r1.messages[0].content?.[0]?.text ?? "").includes("[keyword:"), "marker present");
  // 2. same message repeated → no re-inject (dedup by text)
  const r2 = await listeners["agent/pre-step"]({ agent: { session: { id: "s1" } }, messages: [{ role: "user", content: "Сделай, но коротко" }] }, next);
  ok(r2.messages?.length === 0, "same message deduped");
  // 3. neutral message → no injection
  const r3 = await listeners["agent/pre-step"]({ agent: { session: { id: "s2" } }, messages: [{ role: "user", content: "Продолжай работу" }] }, next);
  ok(r3.messages?.length === 0, "neutral message → no injection");
  // 4. chinese prohibition → russian hint
  const r4 = await listeners["agent/pre-step"]({ agent: { session: { id: "s3" } }, messages: [{ role: "user", content: "не пиши по-китайски" }] }, next);
  ok((r4.messages?.[0]?.content?.[0]?.text ?? "").includes("по-русски"), "language rule hint");
  console.log("\n" + pass + " passed, " + fail + " failed");
  process.exit(fail === 0 ? 0 : 1);
})();
