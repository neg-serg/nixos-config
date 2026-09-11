#!/usr/bin/env node
/**
 * dsh-keymap:user — functional test for the three `tui-keymap-*` fixes.
 *
 * The rebind lands on the TUI's declarative action table, so the assertions that
 * matter are: the anchors and probes (a wrap whose `to` embeds its `from` MUST
 * carry a probe, or every patcher run would nest another wrapper), the spec
 * parser's vocabulary, and the safety net — ActionRegistry.register() throws on a
 * key conflict, so a bad user map must fall back to the built-ins instead of
 * killing startup.
 *
 * Run: node keymap.test.mjs
 */
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const here = path.dirname(fileURLToPath(import.meta.url));
const patchPath = path.join(here, "patch.mjs");
const patchSrc = fs.readFileSync(patchPath, "utf8");

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

function fix(id) {
  const at = patchSrc.indexOf(`id: "${id}"`);
  if (at < 0) return null;
  const hasProbe = /probe: ['"`]/.test(patchSrc.slice(at, patchSrc.indexOf("from: ", at)));
  const fromAt = patchSrc.indexOf("from: ", at);
  const fq = patchSrc[fromAt + 6];
  const fromStart = fromAt + 7;
  const fromEnd = patchSrc.indexOf(fq, fromStart);
  const toAt = patchSrc.indexOf("to: ", at);
  const tq = patchSrc[toAt + 4];
  const toStart = toAt + 5;
  const toEnd = patchSrc.indexOf(tq, toStart);
  const decode = (q, raw) => (q === "`" ? eval(`\`${raw}\``) : q === '"' ? eval(`"${raw}"`) : eval(`'${raw}'`));
  return { hasProbe, from: decode(fq, patchSrc.slice(fromStart, fromEnd)), to: decode(tq, patchSrc.slice(toStart, toEnd)) };
}

const IDS = ["tui-keymap-helper", "tui-keymap-overlay", "tui-keymap-registry"];
const fixes = IDS.map((id) => [id, fix(id)]);

for (const [id, entry] of fixes) {
  ok(entry !== null, `${id}: extracted from patch.mjs`);
  ok(entry.hasProbe, `${id}: declares a probe`);
  ok(!entry.to.includes("`"), `${id}: the inserted/rewritten source has no backticks`);
}
// A wrap that leaves its own anchor in the text is the shape that makes the
// from/to idempotency heuristic useless and the probe load-bearing. These two
// are true replacements (the anchor disappears), so the probe is belt-and-braces
// — pinned here so a future edit that appends instead of wrapping notices.
for (const id of ["tui-keymap-overlay", "tui-keymap-registry"]) {
  const entry = fixes.find(([name]) => name === id)[1];
  ok(!entry.to.includes(entry.from), `${id}: a true replacement (anchor disappears)`);
  ok(entry.to.includes("applyUserKeymap("), `${id}: wraps the table in applyUserKeymap`);
}

// ── patcher mechanics ────────────────────────────────────────────────────────
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "dsh-keymap-"));
const pkgDir = path.join(tmp, "pkg");
fs.mkdirSync(path.join(pkgDir, "lib"), { recursive: true });
fs.writeFileSync(path.join(pkgDir, "package.json"), JSON.stringify({ name: "fixture-tui", version: "0.0.0" }));
const mapPath = path.join(tmp, "i18n.json");
fs.writeFileSync(mapPath, "{}");
const bundlePath = path.join(pkgDir, "lib", "index.js");

const fixture = [
  'import { existsSync, readFileSync } from "node:fs";',
  'import { homedir } from "node:os";',
  'import { join } from "node:path";',
  "function validateActionConflicts(actions) {",
  "  for (let i = 0; i < actions.length; i += 1) for (let j = i + 1; j < actions.length; j += 1) {",
  "    const a = actions[i]; const b = actions[j];",
  '    if ((a.context ?? "global") !== (b.context ?? "global")) continue;',
  "    if (a.when !== void 0 || b.when !== void 0) continue;",
  "    if (a.keys.some((ka) => b.keys.some((kb) => ka.name !== void 0 && kb.name !== void 0 && ka.name === kb.name)))",
  '      throw new Error("conflict: " + a.id + " and " + b.id);',
  "  }",
  "}",
  "var ActionRegistry = class { constructor(actions) { validateActionConflicts(actions); this.actions = actions; } };",
  fixes[0][1].from,
  '\treturn [{ id: "app.quit", keys: [{ name: "ctrl_q" }] }, { id: "session.new", keys: [{ name: "ctrl_n" }] }];',
  "}",
  "function projectKeymapEntries(entries, rows, opts) { return entries; }",
  "function supportsKittyKeyboard(env) { return false; }",
  "const INPUT_LAYER_ROWS = [];",
  "function keymapEntries(env = process.env) {",
  "\t" + fixes[1][1].from,
  "}",
  "class App { init() {",
  "\t\t" + fixes[2][1].from,
  "} }",
  "",
].join("\n");
fs.writeFileSync(bundlePath, fixture);

const runPatcher = () => {
  const res = spawnSync(process.execPath, [patchPath, mapPath, bundlePath], { encoding: "utf8" });
  return `${res.stdout ?? ""}${res.stderr ?? ""}`;
};

const first = runPatcher();
for (const [id] of fixes) ok(first.includes(`fix ${id}: applied`), `patcher applied ${id}`);
const patched = fs.readFileSync(bundlePath, "utf8");
const syntax = spawnSync(process.execPath, ["--check", bundlePath], { encoding: "utf8" });
ok(syntax.status === 0, `the patched bundle parses (${(syntax.stderr ?? "").split("\n")[0] || "ok"})`);

const second = runPatcher();
ok(second.includes("up to date"), "a second run hits the marker fast path (post-patch hash)");
ok(fs.readFileSync(bundlePath, "utf8") === patched, "a second run leaves the bundle byte-identical");
ok((patched.match(/function applyUserKeymap\(/g) ?? []).length === 1, "the helper is not duplicated");
ok((patched.match(/applyUserKeymap\(createBuiltinActions\(/g) ?? []).length === 2, "both call sites are wrapped exactly once");

// ── the inserted helper, exercised ───────────────────────────────────────────
const helperStart = patched.indexOf("/* dsh-keymap:user —");
const helperEnd = patched.indexOf("function createBuiltinActions(", helperStart);
const helperSrc = patched.slice(helperStart, helperEnd);

const buildHelper = (env = {}) => {
  const fakeProcess = { env };
  const factory = new Function(
    "process",
    "join",
    "homedir",
    "existsSync",
    "readFileSync",
    "validateActionConflicts",
    `${helperSrc}
return { dshKeyBinding, dshKeyBindings, applyUserKeymap, dshUserKeymapPath };`
  );
  return {
    api: factory(fakeProcess, path.join, () => tmp, fs.existsSync, fs.readFileSync, (actions) => {
      for (let i = 0; i < actions.length; i += 1)
        for (let j = i + 1; j < actions.length; j += 1) {
          const a = actions[i];
          const b = actions[j];
          if ((a.context ?? "global") !== (b.context ?? "global")) continue;
          if (a.when !== void 0 || b.when !== void 0) continue;
          const clash = a.keys.some((ka) =>
            b.keys.some((kb) => ka.name !== void 0 && kb.name !== void 0 && ka.name === kb.name)
          );
          if (clash) throw new Error(`conflict: ${a.id} and ${b.id}`);
        }
    }),
    env: fakeProcess.env,
  };
};

const specs = [
  ["ctrl+n", { name: "ctrl_n" }],
  ["CTRL+.", { name: "ctrl_." }],
  ["ctrl+enter", { name: "ctrl_return" }],
  ["shift+tab", { name: "shift_tab" }],
  ["enter", { name: "return" }],
  ["esc", { name: "escape" }],
  ["space", { name: "space" }],
  ["up", { name: "up" }],
  ["pgup", { name: "pageup" }],
  ["alt+w", { char: "w", meta: true }],
  ["a", { char: "a" }],
  ["A", { char: "A" }],
];
{
  const { api } = buildHelper();
  for (const [spec, expected] of specs) {
    ok(JSON.stringify(api.dshKeyBinding(spec)) === JSON.stringify(expected), `spec ${JSON.stringify(spec)} → ${JSON.stringify(expected)}`);
  }
  for (const bad of ["", "ctrl+", "ctrl+alt+n", "shift+up", "notakey++", 42, null]) {
    ok(api.dshKeyBinding(bad) === null, `spec ${JSON.stringify(bad)} is rejected`);
  }
  ok(JSON.stringify(api.dshKeyBindings(["ctrl+q", "ctrl+s"])) === JSON.stringify([{ name: "ctrl_q" }, { name: "ctrl_s" }]), "an array becomes several bindings");
  ok(JSON.stringify(api.dshKeyBindings([])) === "[]", "an empty array unbinds");
  ok(api.dshKeyBindings(["ctrl+q", "bogus"]) === null, "one bad entry invalidates the list (the action keeps its built-in)");
}

const ACTIONS = () => [
  { id: "app.quit", keys: [{ name: "ctrl_q" }], category: "Сессия" },
  { id: "session.new", keys: [{ name: "ctrl_n" }] },
  { id: "palette.toggle", keys: [{ name: "ctrl_p" }] },
];

{
  const { api, env } = buildHelper();
  const actions = ACTIONS();
  ok(api.applyUserKeymap(actions) === actions, "no keymap file → the very same array is returned");
  ok(api.dshUserKeymapPath().endsWith(path.join(".dsh-tui", "keymap.json")), "the default path is ~/.dsh-tui/keymap.json");
  env.DSH_TUI_KEYMAP = "/tmp/custom-keymap.json";
  ok(api.dshUserKeymapPath() === "/tmp/custom-keymap.json", "DSH_TUI_KEYMAP overrides the path");
}
{
  const keymapFile = path.join(tmp, "keymap.json");
  fs.writeFileSync(
    keymapFile,
    JSON.stringify({ "app.quit": "ctrl+y", "palette.toggle": ["ctrl+p", "alt+p"], "session.new": [] })
  );
  const { api, env } = buildHelper();
  env.DSH_TUI_KEYMAP = keymapFile;
  const next = api.applyUserKeymap(ACTIONS());
  ok(JSON.stringify(next[0].keys) === JSON.stringify([{ name: "ctrl_y" }]), "app.quit is rebound to ctrl+y");
  ok(next[0].category === "Сессия", "the rest of the action entry is preserved");
  ok(next[0].id === "app.quit", "the action id is preserved");
  ok(next[1].id === "session.new" && next[1].keys.length === 0, "an empty array unbinds the action");
  ok(next[2].keys.length === 2, "an array spec installs two bindings");
  ok(JSON.stringify(next[2].keys) === JSON.stringify([{ name: "ctrl_p" }, { char: "p", meta: true }]), "both palette bindings parsed");
  ok(ACTIONS()[0].keys[0].name === "ctrl_q", "the input table is not mutated");
}
{
  // Ctrl+Shift and Alt+Shift cannot name a distinct binding (the decoder folds
  // them), so they are rejected rather than silently collapsing.
  const { api } = buildHelper();
  ok(api.dshKeyBinding("ctrl+shift+q") === null, "ctrl+shift+<letter> is rejected as inexpressible");
  ok(api.dshKeyBinding("alt+shift+w") === null, "alt+shift+<letter> is rejected as inexpressible");
}
{
  const keymapFile = path.join(tmp, "keymap-bad.json");
  fs.writeFileSync(keymapFile, JSON.stringify({ "app.quit": "ctrl+nonsense+" }));
  const { api, env } = buildHelper();
  env.DSH_TUI_KEYMAP = keymapFile;
  const actions = ACTIONS();
  const next = api.applyUserKeymap(actions);
  ok(next[0] === actions[0], "a typo keeps that action's built-in binding");
}
{
  // A conflicting map must NOT reach ActionRegistry.register(), which throws.
  const keymapFile = path.join(tmp, "keymap-conflict.json");
  fs.writeFileSync(keymapFile, JSON.stringify({ "app.quit": "ctrl+n" }));
  const { api, env } = buildHelper();
  env.DSH_TUI_KEYMAP = keymapFile;
  const actions = ACTIONS();
  const next = api.applyUserKeymap(actions);
  ok(next === actions, "a conflicting map falls back to the built-ins");
  ok(next[0].keys[0].name === "ctrl_q", "the built-in binding survives the fallback");
}
{
  const keymapFile = path.join(tmp, "keymap-broken.json");
  fs.writeFileSync(keymapFile, "{not json");
  const { api, env } = buildHelper();
  env.DSH_TUI_KEYMAP = keymapFile;
  const actions = ACTIONS();
  ok(api.applyUserKeymap(actions) === actions, "malformed JSON falls back silently");
  fs.writeFileSync(keymapFile, "[]");
  ok(api.applyUserKeymap(actions) === actions, "a JSON array (not an object) falls back silently");
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
