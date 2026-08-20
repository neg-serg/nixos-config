#!/usr/bin/env node
/**
 * dsh-desktop functional test (recipe: agent-deferred §0 — real scenario).
 * Usage: node test.mjs [--live]
 *   --live  also runs mutating-free live checks (windows/focused/screenshot,
 *           CUL doctor). Never clicks/types/moves on its own.
 */
import { apply } from "./lib/index.js";
import {
  nativeDoctor, nativeWindows, nativeFocused, nativeScreenshot,
  CulMCP, culDoctor, atspiApps,
} from "./lib/backends.js";

let pass = 0, fail = 0;
const ok = (cond, name) => { if (cond) { pass++; console.log("  ✅ " + name); } else { fail++; console.log("  ❌ " + name); } };

console.log("dsh-desktop tests");

// 1. plugin registers a tool named "desktop" with the full action enum
let registered = null;
apply({ tools: { register: (t) => { registered = t; } } });
ok(registered?.name === "desktop", "tool registered as 'desktop'");
const props = registered?.parameters?.properties ?? {};
const actions = (props.action?.description ?? "").split("|").map((s) => s.trim());
for (const a of ["doctor", "windows", "focused", "screenshot", "focus", "move_window", "resize_window", "type", "press_key", "click", "drag", "scroll", "apps", "state", "set_value", "perform_action"])
  ok(actions.includes(a), "action '" + a + "' in schema");
ok(!!props.backend, "backend param present");
ok(typeof registered.execute === "function", "execute present");
ok(typeof registered.output?.render === "function", "output.render present");

// 2. argument validation (no side effects)
const tool = registered;
async function execThrows(action, args) {
  try { await tool.execute({ action, ...args }, { config: {} }); return false; }
  catch { return true; }
}
(async () => {
  ok(await execThrows("click", {}), "click without target throws");
  ok(await execThrows("drag", {}), "drag without coords throws");
  ok(await execThrows("type", {}), "type without text throws (native)");
  ok(await execThrows("press_key", {}), "press_key without key throws (native)");
  ok(await execThrows("focus", {}), "focus without address throws");
  ok(await execThrows("set_value", { selector: "x" }), "set_value without value throws");

  // 3. native doctor (no daemons)
  const d = await nativeDoctor();
  ok(d.hyprctl === "ok", "hyprctl available");
  ok(typeof d.grim === "string", "grim probed");
  ok(typeof d.wtype === "string", "wtype probed");

  const live = process.argv.includes("--live");
  if (live) {
    // 4. live windows/focused
    try {
      const wins = await nativeWindows();
      ok(Array.isArray(wins) && wins.length > 0, "windows: " + wins.length + " entries");
      ok(wins.every((w) => "address" in w && "title" in w), "windows shape");
    } catch (e) { ok(false, "windows live: " + e.message); }
    try {
      const f = await nativeFocused();
      ok(f && "address" in f, "focused window");
    } catch (e) { ok(false, "focused live: " + e.message); }
    // 5. screenshot (writes /tmp/dsh-desktop-test-shot.png)
    try {
      const s = await nativeScreenshot({ path: "/tmp/dsh-desktop-test-shot.png" });
      ok(s.path && s.path.endsWith(".png"), "screenshot path");
    } catch (e) { ok(false, "screenshot live: " + e.message); }
    // 6. CUL doctor + tools
    const cd = await culDoctor("/home/neg/.local/bin/computer-use-linux");
    ok(cd.ok === true && cd.tools >= 10, "CUL doctor: " + (cd.tools ?? cd.error));
    // 7. AT-SPI apps — may be unavailable; must return structured error, not throw
    const apps = await atspiApps("/home/neg/.local/bin/computer-use-linux");
    ok(apps && (apps.apps || apps.error), "atspi apps structured (" + (apps.error ? "bus down" : "ok") + ")");
    // 8. CUL MCP round-trip (list tools) — spawn/kill lifecycle
    const mcp = new CulMCP("/home/neg/.local/bin/computer-use-linux");
    try {
      await mcp.start();
      const tools = await mcp.tools();
      ok(tools.length >= 10, "CUL tools/list: " + tools.length);
    } catch (e) { ok(false, "CUL mcp: " + e.message); }
    finally { mcp.stop(); }
  } else {
    console.log("  (skip live checks; rerun with --live)");
  }

  console.log("\n" + pass + " passed, " + fail + " failed");
  process.exit(fail === 0 ? 0 : 1);
})();
