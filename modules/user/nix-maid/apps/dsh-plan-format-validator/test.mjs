#!/usr/bin/env node
/** dsh-plan-format-validator functional test. */
import { apply } from "./lib/index.js";
let pass = 0, fail = 0;
const ok = (c, n) => { if (c) { pass++; console.log("  ✅ " + n); } else { fail++; console.log("  ❌ " + n); } };
const listeners = {};
apply({ on: (evt, fn) => { listeners[evt] = fn; } });
ok(typeof listeners["tools/pre-execute"] === "function", "pre-execute listener registered");
const nextAllow = async () => ({ kind: "allow" });
const goodPlan = "# Рефакторинг x\n\n## Цель\nСделать y.\n\n## Шаги\n1. Правка a.\n2. Правка b.\n\n## Риски\nПроверка: команда, ожидание.";
const barePlan = "Сделать y";
const noSections = "# Рефакторинг x\nпросто текст без секций";
(async () => {
  // 1. good plan → allow
  const d1 = await listeners["tools/pre-execute"]({ name: "exit_plan_mode", args: { plan: goodPlan } }, nextAllow);
  ok(d1.kind === "allow", "well-formed plan allowed");
  // 2. bare text → deny (no heading)
  const d2 = await listeners["tools/pre-execute"]({ name: "exit_plan_mode", args: { plan: barePlan } }, nextAllow);
  ok(d2.kind === "deny", "bare plan denied");
  ok((d2.reason ?? "").includes("заголовок"), "reason names heading");
  // 3. heading but no sections → deny
  const d3 = await listeners["tools/pre-execute"]({ name: "exit_plan_mode", args: { plan: noSections } }, nextAllow);
  ok(d3.kind === "deny", "no-sections plan denied");
  ok((d3.reason ?? "").includes("секции"), "reason names sections");
  // 4. empty plan → deny
  const d4 = await listeners["tools/pre-execute"]({ name: "exit_plan_mode", args: { plan: "" } }, nextAllow);
  ok(d4.kind === "deny", "empty plan denied");
  // 5. other tool untouched
  const d5 = await listeners["tools/pre-execute"]({ name: "edit", args: { file_path: "/x.md" } }, nextAllow);
  ok(d5.kind === "allow", "edit untouched");
  console.log("\n" + pass + " passed, " + fail + " failed");
  process.exit(fail === 0 ? 0 : 1);
})();
