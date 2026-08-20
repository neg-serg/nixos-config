#!/usr/bin/env node
/** dsh-notepad-write-guard functional test. */
import { apply } from "./lib/index.js";
let pass = 0, fail = 0;
const ok = (c, n) => { if (c) { pass++; console.log("  ✅ " + n); } else { fail++; console.log("  ❌ " + n); } };
const listeners = {};
apply({ on: (evt, fn) => { listeners[evt] = fn; } });
ok(typeof listeners["tools/pre-execute"] === "function", "pre-execute listener registered");
const nextAllow = async () => ({ kind: "allow" });
(async () => {
  // 1. write to notepad → deny
  const d1 = await listeners["tools/pre-execute"]({ name: "write", args: { path: "/etc/nixos/.agent/notepads/x/learnings.md" } }, nextAllow);
  ok(d1.kind === "deny", "write to notepad denied");
  ok((d1.reason ?? "").includes("append-only"), "reason mentions append-only");
  // 2. edit outside notepads → allow
  const d2 = await listeners["tools/pre-execute"]({ name: "edit", args: { file_path: "/etc/nixos/modules/x.nix" } }, nextAllow);
  ok(d2.kind === "allow", "edit outside notepads allowed");
  // 3. read_document of notepad → deny (write-type tool on read path is still guarded)
  const d3 = await listeners["tools/pre-execute"]({ name: "read_document", args: { file_path: "/x/.agent/notepads/y/verification.md" } }, nextAllow);
  ok(d3.kind === "deny", "read_document on notepad denied");
  // 4. bash → untouched
  const d4 = await listeners["tools/pre-execute"]({ name: "bash", args: { command: "cat .agent/notepads/x.md" } }, nextAllow);
  ok(d4.kind === "allow", "bash untouched (guard is tool-level)");
  console.log("\n" + pass + " passed, " + fail + " failed");
  process.exit(fail === 0 ? 0 : 1);
})();
