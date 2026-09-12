#!/usr/bin/env node
/**
 * dsh-tui-boot — functional test for the `boot-progress-*` fixes.
 *
 * These fixes draw one self-clearing status line while the harness mounts the
 * plugin tree and the TUI resumes a session, then wipe it right before the
 * first real frame. The failure modes worth pinning are: the anchors existing
 * exactly once in a pristine bundle (a drifted bundle must skip the fix, not
 * corrupt it), the helper staying a complete no-op off a TTY and under its
 * kill switches, the line appearing as soon as the runner mounts (a slow boot
 * must be visible from the first phase), and the line being cleared exactly
 * once per drawn session — never after the TUI has painted.
 *
 * Run: node boot-progress.test.mjs
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

const IDS = [
  "boot-progress-helper",
  "boot-progress-start",
  "boot-progress-services",
  "boot-progress-host-services",
  "boot-progress-settings",
  "boot-progress-session",
  "boot-progress-sessions-list",
  "boot-progress-help",
  "boot-progress-first-frame",
  "boot-progress-safety",
];
const fixes = IDS.map((id) => [id, fix(id)]);

for (const [id, entry] of fixes) {
  ok(entry !== null && typeof entry.from === "string" && typeof entry.to === "string", `${id}: extracted from patch.mjs`);
}
{
  const withTo = fixes.filter(([, e]) => e && e.to);
  ok(withTo.length === IDS.length, "every boot-progress fix has a from/to pair");
  for (const [id, entry] of withTo) {
    // Replacement fixes drop their anchor; append-style ones keep it. `to`
    // must always contain the code that makes the fix observable.
    ok(entry.to.length > entry.from.length, `${id}: the replacement adds text`);
  }
  const allTo = withTo.map(([, e]) => e.to).join("\n");
  ok(!allTo.includes("`"), "the inserted sources contain no backticks (extraction stays exact)");
  ok(allTo.includes("function createBootProgress(stream, env) {"), "the helper fix inserts createBootProgress");
  ok(allTo.includes("let dshBootProgress = null;"), "the helper fix declares the module-level handle");
  ok(allTo.includes("env?.DSH_TUI_BOOT_QUIET"), "the helper honours the DSH_TUI_BOOT_QUIET kill switch");
}

// ── patcher mechanics against a synthetic bundle ──────────────────────────────
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "dsh-boot-progress-"));
const pkgDir = path.join(tmp, "pkg");
fs.mkdirSync(path.join(pkgDir, "lib"), { recursive: true });
fs.writeFileSync(path.join(pkgDir, "package.json"), JSON.stringify({ name: "fixture-tui", version: "0.0.0" }));
const mapPath = path.join(tmp, "i18n.json");
fs.writeFileSync(mapPath, "{}");
const bundlePath = path.join(pkgDir, "lib", "index.js");

const fixture = [
  'const name = "tui-runner";',
  "function apply(ctx, config = {}) {",
  "\tconst stdin = config.stdin ?? process.stdin;",
  "\tconst stdout = config.stdout ?? process.stdout;",
  '\tctx.inject(["sessions"], (runtimeCtx) => {',
  "\t\tconst requestHostExit = () => {",
  "\t\t\treturn 0;",
  "\t\t};",
  "\t\tconst attachPromise = app.attach().catch((err) => {",
  "\t\t\treturn err;",
  "\t\t});",
  "\t});",
  "}",
  "class TuiApp {",
  "\tflushLiveRender() {",
  "\t\tthis.renderBatcher.flushNow();",
  "\t}",
  "\tasync attach(initialSessionId) {",
  '\t\tif (this.disposed) throw new Error("disposed");',
  "\t\tawait this.waitForHostServices();",
  "\t\tconst args = [];",
  "\t\tconst flags = [];",
  "\t\tconst wantHelp = flags.includes('--help');",
  "\t\tconst wantVersion = flags.includes('--version');",
  "\t\tif (wantHelp || wantVersion) {",
  "\t\t\treturn;",
  "\t\t}",
  '\t\tawait this.waitForServicesReady(["settings", "credentials"]);',
  "\t\tconst target = undefined;",
  "\t\tif (target !== void 0) await this.switchSession(target);",
  "\t\tawait this.renderRestorableSessions();",
  '\t\tfor (const w of this.themeWarnings) this.echoWarn("w", "hint");',
  "\t\tthis.flushLiveRender();",
  "\t}",
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
// Replacement fixes rewrite their anchor; append-style ones keep it. `probe`
// is what makes a replacement idempotent.
const REPLACEMENTS = new Set(["boot-progress-safety", "boot-progress-first-frame"]);
for (const [id, entry] of fixes) {
  const probe = new RegExp(`id: "${id}"[\\s\\S]*?probe: "`).test(patchSrc);
  ok(probe, `${id}: declares a probe so re-runs cannot duplicate it`);
  if (REPLACEMENTS.has(id)) {
    ok(patched.includes(entry.to.trim()) && !patched.includes(entry.from), `${id}: rewires its anchor`);
  } else {
    ok(patched.includes(entry.from), `${id}: keeps its anchor in place (append-style)`);
  }
}
ok((patched.match(/function createBootProgress\(stream, env\) \{/g) ?? []).length === 1, "the helper is inserted exactly once");
ok((patched.match(/let dshBootProgress = null;/g) ?? []).length === 1, "the module-level handle is declared exactly once");
ok((patched.match(/dshBootProgress\?\.stop\(\);/g) ?? []).length === 2, "the line is stopped on the help/version and first-frame paths");
ok(fs.existsSync(`${bundlePath}.orig`), "pristine backup written");

// The patched fixture must be valid JavaScript.
const syntax = spawnSync(process.execPath, ["--check", bundlePath], { encoding: "utf8" });
ok(syntax.status === 0, `the patched bundle parses (${(syntax.stderr ?? "").split("\n")[0] || "ok"})`);

const second = runPatcher();
ok(second.includes("up to date"), "a second run re-applies nothing");
ok(fs.readFileSync(bundlePath, "utf8") === patched, "a second run leaves the bundle byte-identical");

// ── the inserted helper, exercised ───────────────────────────────────────────
const helperStart = patched.indexOf("/* dsh-tui-boot — one self-clearing");
const helperEnd = patched.indexOf("/* dsh-tui-boot — module-level", helperStart);
const helperSrc = patched.slice(helperStart, helperEnd);
ok(helperSrc.includes("function createBootProgress") && helperSrc.includes("CLEAR_LINE"), "the helper region extracts cleanly");

const CLEAR = String.fromCharCode(13, 27) + "[2K";
const buildHelper = () => new Function(`${helperSrc}\nreturn createBootProgress;`)();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const fakeStream = (isTTY) => ({
  isTTY,
  out: "",
  write(chunk) {
    this.out += chunk;
  },
});

{
  const stream = fakeStream(false);
  const api = buildHelper()(stream, {});
  api.start("Загрузка");
  await sleep(220);
  api.step("Сессия");
  api.stop();
  ok(stream.out === "", "a non-TTY stream never sees a byte");
}
{
  const stream = fakeStream(true);
  const api = buildHelper()(stream, { DSH_TUI_BOOT_QUIET: "1" });
  api.start("Загрузка");
  await sleep(220);
  api.stop();
  ok(stream.out === "", "DSH_TUI_BOOT_QUIET=1 disables the line");
}
{
  const stream = fakeStream(true);
  const api = buildHelper()(stream, { CI: "true" });
  api.start("Загрузка");
  await sleep(220);
  api.stop();
  ok(stream.out === "", "CI=true disables the line");
}
{
  const stream = fakeStream(true);
  const api = buildHelper()(stream, {});
  api.start("Загрузка dsh…");
  ok(stream.out.includes("Загрузка dsh…") && /\d+\.\d+s/.test(stream.out), "start() draws the phase and elapsed seconds immediately");
  const before = stream.out;
  api.step("Возобновление сессии…");
  ok(stream.out !== before && stream.out.includes("Возобновление сессии…"), "step() advances the phase immediately");
  api.stop();
  ok(stream.out.endsWith(CLEAR), "stop() wipes the line it drew");
  const cleared = stream.out;
  api.stop();
  ok(stream.out === cleared, "a second stop() is a no-op (no second wipe)");
  await sleep(200);
  ok(stream.out === cleared, "no timer survives stop()");
}
{
  const stream = fakeStream(true);
  const api = buildHelper()(stream, {});
  ok(api.start("once") !== null, "start() returns the api for chaining");
  const once = stream.out;
  api.start("twice");
  ok(stream.out === once, "a second start() does not stack a second timer");
  api.stop();
}
{
  const stream = fakeStream(true);
  const api = buildHelper()(stream, {});
  api.step("too early");
  ok(stream.out === "", "step() before start() is inert");
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
