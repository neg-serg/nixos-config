#!/usr/bin/env node
/**
 * dsh-notify:osc — functional test for the `notify-osc` fix in patch.mjs.
 *
 * Two halves:
 *   A. patcher mechanics: run the real patcher against a synthetic bundle that
 *      carries the exact upstream `from` literal, then assert the fix landed
 *      and that a second run is a no-op (idempotency is what the activation
 *      script relies on);
 *   B. decision table: pull the inserted helper out of the *patched* text and
 *      exercise it with fakes, including the regression this fix exists for —
 *      an OSC notification must still fire when SSH_* is set, because the
 *      escape sequence is bytes on the pty rather than a session-bus call.
 *
 * Run: node notify-osc.test.mjs
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
const ok = (cond, name) => {
  if (cond) {
    pass += 1;
    console.log(`  ✅ ${name}`);
  } else {
    fail += 1;
    console.log(`  ❌ ${name}`);
  }
};

// ── extract the fix entry from patch.mjs (single source of truth) ────────────
const entryStart = patchSrc.indexOf('id: "notify-osc"');
if (entryStart < 0) {
  console.error("notify-osc fix not found in patch.mjs");
  process.exit(1);
}
const fromStart = patchSrc.indexOf("from: '", entryStart) + "from: '".length;
const fromEnd = patchSrc.indexOf("'", fromStart);
const upstreamAnchor = eval(`'${patchSrc.slice(fromStart, fromEnd)}'`);
const toStart = patchSrc.indexOf("to: `", entryStart) + "to: `".length;
const toEnd = patchSrc.indexOf("`", toStart);
const insertedSource = eval(`\`${patchSrc.slice(toStart, toEnd)}\``);

ok(upstreamAnchor.startsWith("function notifyOs(payload, prefs) {"), "upstream anchor extracted");
ok(insertedSource.includes("function tryOscNotify"), "inserted helper extracted");
ok(insertedSource.includes("function notifyOs(payload, prefs) {"), "helper rewrites notifyOs");
ok(!patchSrc.slice(toStart, toEnd).includes("`"), "helper source has no backticks (extraction is exact)");

// ── A. patcher mechanics ─────────────────────────────────────────────────────
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "dsh-notify-osc-"));
const pkgDir = path.join(tmp, "pkg");
fs.mkdirSync(path.join(pkgDir, "lib"), { recursive: true });
fs.writeFileSync(
  path.join(pkgDir, "package.json"),
  JSON.stringify({ name: "fixture-tui", version: "0.0.0" })
);
const mapPath = path.join(tmp, "i18n.json");
fs.writeFileSync(mapPath, "{}");
const bundlePath = path.join(pkgDir, "lib", "index.js");

const fixture = [
  String.raw`function flag(env, key) { return env[key] === "1" || env[key] === "true"; }`,
  String.raw`function sanitizeNotifyText(text, max) {
	const flat = String(text).replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim();
	return flat.length <= max ? flat : flat.slice(0, max - 1) + "…";
}`,
  String.raw`async function sendOsNotify(payload, opts = {}) { return false; }`,
  upstreamAnchor,
  "",
].join("\n");
fs.writeFileSync(bundlePath, fixture);

const runPatcher = () => {
  const res = spawnSync(process.execPath, [patchPath, mapPath, bundlePath], {
    encoding: "utf8",
  });
  return `${res.stdout ?? ""}${res.stderr ?? ""}`;
};

runPatcher();
const patched = fs.readFileSync(bundlePath, "utf8");
ok(patched.includes("/* dsh-notify:osc —"), "patcher inserted the helper");
ok(patched.includes("if (tryOscNotify(payload, prefs)) return;"), "patcher rewired notifyOs");
ok(!patched.includes(upstreamAnchor), "old notifyOs body is gone");
ok(fs.existsSync(`${bundlePath}.orig`), "pristine backup written");
ok(
  fs.existsSync(path.join(pkgDir, ".dsh-tui-ru.json")),
  "marker written (idempotency gate)"
);

// The marker stores the pre-patch hash, so the run right after patching still
// re-applies the fixes; the "up to date" fast path only engages on the run
// after that. Notify-osc must report "already applied" rather than re-insert.
const secondOut = runPatcher();
ok(secondOut.includes("fix notify-osc: already applied"), "second run re-applies nothing (notify-osc already applied)");
ok(
  fs.readFileSync(bundlePath, "utf8") === patched,
  "second run leaves the bundle byte-identical"
);
const thirdOut = runPatcher();
ok(thirdOut.includes("up to date"), "third run hits the marker fast path");

// ── B. decision table on the patched artifact ────────────────────────────────
const helperStart = patched.indexOf("/* dsh-notify:osc —");
const helperSource = patched.slice(helperStart);
const sentOsNotifyCalls = [];
const build = (isTTY = true) => {
  const writes = [];
  const fakeProcess = { env: {}, stdout: { isTTY, write: (s) => writes.push(s) } };
  const fn = new Function(
    "sanitizeNotifyText",
    "flag",
    "sendOsNotify",
    "process",
    `${helperSource}
return { oscNotifyProtocol, oscNotifySequence, oscShouldNotify, tryOscNotify, notifyOs };`
  );
  const flat = (text, max) => {
    const f = String(text).replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim();
    return f.length <= max ? f : `${f.slice(0, max - 1)}…`;
  };
  const api = fn(
    flat,
    (env, key) => env[key] === "1" || env[key] === "true",
    (...args) => {
      sentOsNotifyCalls.push(args);
    },
    fakeProcess
  );
  return { api, writes };
};

const payload = { title: "DeepSeek Harness", body: "Turn complete" };
const cases = [
  ["kitty via KITTY_WINDOW_ID", { KITTY_WINDOW_ID: "1" }, "kitty"],
  ["kitty via TERM", { TERM: "xterm-kitty" }, "kitty"],
  ["iTerm2", { TERM_PROGRAM: "iTerm.app" }, "osc9"],
  ["WezTerm", { TERM_PROGRAM: "WezTerm" }, "osc9"],
  ["Ghostty", { TERM_PROGRAM: "ghostty" }, "osc9"],
  ["Ghostty via TERM", { TERM: "xterm-ghostty" }, "osc9"],
  ["unknown terminal → fallback", { TERM_PROGRAM: "Apple_Terminal", TERM: "xterm-256color" }, null],
  ["DSH_NOTIFY_OSC=0 → fallback", { KITTY_WINDOW_ID: "1", DSH_NOTIFY_OSC: "0" }, null],
  ["DSH_NOTIFY_OSC=1 → force OSC 9", { TERM: "dumb", DSH_NOTIFY_OSC: "1" }, "osc9"],
];
for (const [name, env, expected] of cases) {
  const { api } = build();
  ok(api.oscNotifyProtocol(env) === expected, `protocol: ${name}`);
}

{
  const { api, writes } = build();
  ok(api.tryOscNotify(payload, undefined, { KITTY_WINDOW_ID: "1" }) === true, "kitty: writes");
  ok(writes.length === 1 && writes[0].startsWith("\u001b]99;;"), "kitty: OSC 99 prefix");
  ok(writes[0].endsWith("\u001b\\"), "kitty: ST terminator");
  ok(writes[0].includes("DeepSeek Harness — Turn complete"), "kitty: title + body payload");
}
{
  const { api, writes } = build();
  ok(api.tryOscNotify(payload, undefined, { TERM_PROGRAM: "iTerm.app" }) === true, "iTerm2: writes");
  ok(writes[0] === "\u001b]9;DeepSeek Harness — Turn complete\u0007", "iTerm2: OSC 9 + BEL");
}
{
  // The reason this fix exists: SSH must not silence the notification.
  const { api, writes } = build();
  const sshEnv = { KITTY_WINDOW_ID: "1", SSH_CONNECTION: "10.0.0.1 22 10.0.0.2 54321" };
  ok(api.tryOscNotify(payload, undefined, sshEnv) === true, "SSH: OSC notification still fires");
  ok(writes.length === 1, "SSH: exactly one write");
}
{
  const { api } = build();
  ok(api.tryOscNotify(payload, { notifyOs: false }, { KITTY_WINDOW_ID: "1" }) === false, "prefs notifyOs=false: suppressed");
  ok(api.tryOscNotify(payload, undefined, { KITTY_WINDOW_ID: "1", DSH_TUI_SKIP_NOTIFY: "1" }) === false, "DSH_TUI_SKIP_NOTIFY=1: suppressed");
  ok(api.tryOscNotify(payload, undefined, { KITTY_WINDOW_ID: "1", CI: "true" }) === false, "CI: suppressed");
}
{
  const { api, writes } = build(false);
  ok(api.tryOscNotify(payload, undefined, { KITTY_WINDOW_ID: "1" }) === false, "non-TTY stdout: no escape written");
  ok(writes.length === 0, "non-TTY stdout: nothing on the wire");
}
{
  const { api, writes } = build();
  const before = sentOsNotifyCalls.length;
  api.notifyOs(payload, undefined);
  ok(writes.length === 0, "notifyOs on unknown terminal writes no escape");
  ok(sentOsNotifyCalls.length === before + 1, "notifyOs falls back to sendOsNotify");
  const { api: kApi, writes: kWrites } = build();
  kApi.notifyOs(payload, undefined);
  ok(kWrites.length === 0, "notifyOs passes no env → falls back when process.env is empty");
}
{
  const { api, writes } = build();
  api.tryOscNotify(
    { title: "ok\u001b]9;injected", body: "body\u0007plain" },
    undefined,
    { KITTY_WINDOW_ID: "1" }
  );
  const raw = writes[0] ?? "";
  ok(
    (raw.match(/\u001b/g) ?? []).length === 2 && !raw.includes("\u0007"),
    "payload control chars are neutralised (exactly the OSC introducer + ST remain)"
  );
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
