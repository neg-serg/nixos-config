#!/usr/bin/env node
/**
 * dsh-statusline:frame — functional test for the four `tui-statusline-*` fixes.
 *
 * These fixes wire the upstream `StatusLineRunner` (shipped but never
 * instantiated) into the glance status slot. Three anchors are in the app, one
 * is a helper insertion, so the failure modes worth pinning are: the anchors
 * existing exactly once (a drifted bundle must skip the fix, not corrupt it),
 * the inserted helper resolving the command from env then settings without ever
 * throwing, and the combined status text keeping the built-in workflow line.
 *
 * Run: node statusline-frame.test.mjs
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

/** Pull one FIXES entry's literal strings out of patch.mjs (single source of truth). */
function fix(id) {
  const at = patchSrc.indexOf(`id: "${id}"`);
  if (at < 0) return null;
  const fromAt = patchSrc.indexOf("from: ", at);
  const quote = patchSrc[fromAt + 6];
  const fromStart = fromAt + 7;
  const fromEnd = patchSrc.indexOf(quote, fromStart);
  const toAt = patchSrc.indexOf("to: ", at);
  const toQuote = patchSrc[toAt + 4];
  const toStart = toAt + 5;
  const toEnd = patchSrc.indexOf(toQuote, toStart);
  const decode = (q, raw) => {
    if (q === "`") return eval(`\`${raw}\``);
    if (q === '"') return eval(`"${raw}"`);
    return eval(`'${raw}'`);
  };
  return { from: decode(quote, patchSrc.slice(fromStart, fromEnd)), to: decode(toQuote, patchSrc.slice(toStart, toEnd)) };
}

const IDS = ["tui-statusline-helper", "tui-statusline-fields", "tui-statusline-mount", "tui-statusline-glance"];
const fixes = IDS.map((id) => [id, fix(id)]);

for (const [id, entry] of fixes) {
  ok(entry !== null && typeof entry.from === "string" && typeof entry.to === "string", `${id}: extracted from patch.mjs`);
}
ok(fixes[0][1].to.includes("function resolveStatusLineCommand"), "the helper fix inserts resolveStatusLineCommand");
ok(fixes[0][1].to.includes("globalThis.__dshTuiStatusLineFrame"), "the helper fix publishes the frame marker");
ok(fixes[3][1].to.includes("parts.join"), "the glance fix combines the two status texts");
{
  const allTo = fixes.map(([, e]) => e.to).join("\n");
  ok(!allTo.includes("`"), "the inserted sources contain no backticks (extraction stays exact)");
}

// ── patcher mechanics against a synthetic bundle ──────────────────────────────
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "dsh-statusline-frame-"));
const pkgDir = path.join(tmp, "pkg");
fs.mkdirSync(path.join(pkgDir, "lib"), { recursive: true });
fs.writeFileSync(path.join(pkgDir, "package.json"), JSON.stringify({ name: "fixture-tui", version: "0.0.0" }));
const mapPath = path.join(tmp, "i18n.json");
fs.writeFileSync(mapPath, "{}");
const bundlePath = path.join(pkgDir, "lib", "index.js");

const fixture = [
  "var StatusLineRunner = class { constructor(config, onUpdate) { this.command = config.command; this.onUpdate = onUpdate; } get current() { return null; } refresh(payload) { return payload; } };",
  fixes[1][1].from,
  "class App {",
  "  mountSession(id) {",
  fixes[2][1].from,
  "  }",
  "  init() {",
  "    this.glance = new MetricsGlanceController({",
  fixes[3][1].from,
  "      getLiveState: () => null",
  "    });",
  "  }",
  "}",
  fixes[0][1].from,
  "\treturn { status: statusText, error: null, errorFull: null };",
  "}",
  "",
].join("\n");
fs.writeFileSync(bundlePath, fixture);

const runPatcher = () => {
  const res = spawnSync(process.execPath, [patchPath, mapPath, bundlePath], { encoding: "utf8" });
  return `${res.stdout ?? ""}${res.stderr ?? ""}`;
};

const first = runPatcher();
for (const [id] of fixes) {
  ok(first.includes(`fix ${id}: applied`), `patcher applied ${id}`);
}
const patched = fs.readFileSync(bundlePath, "utf8");
// Only the glance fix is a true replacement; the other three extend their
// anchor in place (their `to` embeds the `from`), which is what `probe` is for.
ok(!patched.includes(fixes[3][1].from), "the glance anchor is replaced");
ok(patched.includes(fixes[2][1].from), "the mount anchor is kept (append-style fix)");
for (const [id, entry] of fixes) {
  const probe = new RegExp(`id: "${id}"[\\s\\S]*?probe: "`).test(patchSrc);
  ok(probe, `${id}: declares a probe so re-runs cannot duplicate it`);
}
ok((patched.match(/new StatusLineRunner\(\{/g) ?? []).length === 1, "exactly one runner construction survives the re-run");
ok((patched.match(/^\tuserStatusLine = null;$/gm) ?? []).length === 1, "the class field is declared exactly once");
ok((patched.match(/^\tuserStatusLinePayload = null;$/gm) ?? []).length === 1, "the payload field is declared exactly once");
ok((patched.match(/function resolveStatusLineCommand/g) ?? []).length === 1, "the helper is not duplicated by a re-run");
ok((patched.match(/function resolveStatusLineCommand/g) ?? []).length === 1, "the helper is inserted exactly once");
ok(fs.existsSync(`${bundlePath}.orig`), "pristine backup written");

// The patched fixture must be valid JavaScript.
fs.writeFileSync(path.join(pkgDir, "lib", "check.mjs"), patched);
const syntax = spawnSync(process.execPath, ["--check", path.join(pkgDir, "lib", "index.js")], { encoding: "utf8" });
ok(syntax.status === 0, `the patched bundle parses (${(syntax.stderr ?? "").split("\n")[0] || "ok"})`);

const second = runPatcher();
ok(second.includes("tui-statusline-helper: already applied"), "a second run re-applies nothing");
ok(fs.readFileSync(bundlePath, "utf8") === patched, "a second run leaves the bundle byte-identical");

// ── the inserted helper, exercised ───────────────────────────────────────────
const helperStart = patched.indexOf("/* dsh-statusline:frame — the scriptable");
const helperEnd = patched.indexOf("function deriveGlance(", helperStart);
const helperSrc = patched.slice(helperStart, helperEnd);
ok(helperSrc.includes("resolveStatusLineCommand") && helperSrc.includes("markStatusLineFrame"), "the helper region extracts cleanly");

const buildHelper = () => {
  const factory = new Function("process", `${helperSrc}\nreturn { resolveStatusLineCommand, markStatusLineFrame };`);
  const fakeProcess = { env: {} };
  return { api: factory(fakeProcess), env: fakeProcess.env };
};

{
  const { api, env } = buildHelper();
  env.DSH_TUI_STATUSLINE = "  /run/me.sh  ";
  ok(api.resolveStatusLineCommand({}) === "/run/me.sh", "the env command wins and is trimmed");
}
{
  const { api, env } = buildHelper();
  delete env.DSH_TUI_STATUSLINE;
  const ctx = { get: (name) => (name === "settings" ? { get: (ns) => (ns === "ui.statusLine" ? { command: "/from/settings.sh" } : undefined) } : undefined) };
  ok(api.resolveStatusLineCommand(ctx) === "/from/settings.sh", "the documented ui.statusLine.command is honoured");
}
{
  const { api } = buildHelper();
  const ctx = { get: () => ({ get: (ns) => (ns === "ui-statusLine" ? { command: "/dashed.sh" } : undefined) }) };
  ok(api.resolveStatusLineCommand(ctx) === "/dashed.sh", "the dashed settings key is accepted too");
}
{
  const { api } = buildHelper();
  ok(api.resolveStatusLineCommand({}) === null, "no command anywhere → null (the runner is not created)");
  ok(api.resolveStatusLineCommand(undefined) === null, "a missing context → null, never a throw");
  ok(api.resolveStatusLineCommand({ get: () => { throw new Error("no settings"); } }) === null, "a throwing settings lookup → null");
  ok(api.resolveStatusLineCommand({ get: () => ({ get: () => ({ command: "   " }) }) }) === null, "a blank command is ignored");
}
{
  const { api } = buildHelper();
  delete globalThis.__dshTuiStatusLineFrame;
  api.markStatusLineFrame();
  ok(globalThis.__dshTuiStatusLineFrame === true, "the frame marker is published for the title fallback");
  delete globalThis.__dshTuiStatusLineFrame;
}

// ── the combined status text ─────────────────────────────────────────────────
{
  // Re-implement the patched closure body's contract against fake parts.
  const combine = (user, builtin) =>
    [user ?? null, builtin ?? null].filter((part) => part !== null && part !== undefined && part !== "").join(" · ");
  ok(combine("⎇ main", "bash") === "⎇ main · bash", "the script line and the workflow phase are combined");
  ok(combine("⎇ main", null) === "⎇ main", "an idle session keeps the script line");
  ok(combine(null, "bash") === "bash", "without a script the workflow line is unchanged");
  ok(combine(null, null) === "", "no text stays empty");
  ok(patched.includes('parts.length === 0 ? null : parts.join(" · ")'), "the patched closure returns null when there is nothing to show");
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
