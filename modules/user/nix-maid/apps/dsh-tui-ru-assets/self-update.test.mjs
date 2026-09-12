#!/usr/bin/env node
/**
 * dsh-tui self-update — functional test for the `self-update-park-harness` fix.
 *
 * The TUI's startup self-updater runs `pnpm add <pkg>@<latest>` in the profile
 * dir. On this host node_modules/@deepseek-ai is a symlink into the read-only
 * nix store, so pnpm's importPackage writes through it and dies with
 * ERR_PNPM_EROFS before the package lands (the failure notice blames the
 * network). The fix parks the symlink around the child and restores it
 * afterwards, then re-runs the repo's translation patch so the host cannot
 * restart into the raw Chinese bundle.
 *
 * Failure modes pinned here: the anchor existing verbatim in a pristine bundle
 * (a drifted upstream function must skip, not corrupt), idempotent re-runs, the
 * patched bundle parsing, and — with the child stubbed — the symlink being
 * parked before the install and restored after it, on success and on failure,
 * with the re-patch fired only on success.
 *
 * Run: node self-update.test.mjs
 */
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const here = path.dirname(fileURLToPath(import.meta.url));
const patchPath = path.join(here, "patch.mjs");

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

/** The pristine upstream function, verbatim — the fix's `from` anchor. */
const FIXTURE_FN = [
  "function installNpmVersion(latest, profileDir, timeoutMs = 6e4) {",
  "\tconst { command, args, label } = installCommandFor(detectPackageManager(profileDir), latest);",
  "\treturn new Promise((resolve, reject) => {",
  "\t\tconst child = spawn(command, args, {",
  "\t\t\tcwd: profileDir,",
  '\t\t\tstdio: "ignore",',
  "\t\t\twindowsHide: true",
  "\t\t});",
  "\t\tconst timer = setTimeout(() => {",
  "\t\t\tchild.kill();",
  "\t\t\treject(/* @__PURE__ */ new Error(`${label} timed out`));",
  "\t\t}, timeoutMs);",
  '\t\tchild.on("error", (err) => {',
  "\t\t\tclearTimeout(timer);",
  "\t\t\treject(err);",
  "\t\t});",
  '\t\tchild.on("exit", (code) => {',
  "\t\t\tclearTimeout(timer);",
  "\t\t\tif (code === 0) resolve();",
  '\t\t\telse reject(/* @__PURE__ */ new Error(`${label} exited ${code ?? "null"}`));',
  "\t\t});",
  "\t});",
  "}",
].join("\n");

// ── patcher mechanics against a synthetic bundle ──────────────────────────────
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "dsh-self-update-"));
const pkgDir = path.join(tmp, "pkg");
fs.mkdirSync(path.join(pkgDir, "lib"), { recursive: true });
fs.writeFileSync(path.join(pkgDir, "package.json"), JSON.stringify({ name: "fixture-tui", version: "0.0.0" }));
const mapPath = path.join(tmp, "i18n.json");
fs.writeFileSync(mapPath, "{}");
const bundlePath = path.join(pkgDir, "lib", "index.js");

const fixture = [
  'const name = "tui-runner";',
  'function detectPackageManager() { return "pnpm"; }',
  'function installCommandFor(pm, latest) { return { command: pm, args: ["add", latest], label: pm + " add" }; }',
  FIXTURE_FN,
  "",
].join("\n");
fs.writeFileSync(bundlePath, fixture);

const runPatcher = () => {
  const res = spawnSync(process.execPath, [patchPath, mapPath, bundlePath], { encoding: "utf8" });
  return `${res.stdout ?? ""}${res.stderr ?? ""}`;
};

const first = runPatcher();
ok(first.includes("fix self-update-park-harness: applied"), "patcher applies self-update-park-harness to a pristine bundle");
const patched = fs.readFileSync(bundlePath, "utf8");
ok(!patched.includes(FIXTURE_FN), "the pristine anchor is gone after patching");
ok(patched.includes("dsh-tui-nix — park the @deepseek-ai store symlink"), "the parking marker lands in the bundle");
ok(patched.includes("readdirSync(join(profileDir, \"node_modules\"), { withFileTypes: true })"), "the fix detects the symlink by dirent type");
ok(patched.includes("join(homedir(), \".local\", \"bin\", \"dsh-tui-repatch\")"), "the fix re-patches through the repo helper");
ok(fs.existsSync(`${bundlePath}.orig`), "pristine backup written");

const syntax = spawnSync(process.execPath, ["--check", bundlePath], { encoding: "utf8" });
ok(syntax.status === 0, `the patched bundle parses (${(syntax.stderr ?? "").split("\n")[0] || "ok"})`);

const second = runPatcher();
ok(second.includes("up to date"), "a second run re-applies nothing");
ok(fs.readFileSync(bundlePath, "utf8") === patched, "a second run leaves the bundle byte-identical");

// ── the patched installer, exercised with a stubbed child ─────────────────────
const fnStart = patched.indexOf("function installNpmVersion(");
const fnEnd = patched.indexOf("\n}\n", fnStart);
const fnSrc = patched.slice(fnStart, fnEnd + 2);
ok(fnSrc.includes("const unpark = () => {") && fnSrc.includes("const repatch = () => {"), "the patched function extracts cleanly");

const PKG_DIR = "/home/test/.dsh/profiles/tui";
const AI_DIR = `${PKG_DIR}/node_modules/@deepseek-ai`;

function loadInstaller(state) {
  const calls = { rename: [], rm: [], spawn: [], spawnSync: [] };
  const deps = {
    join: path.join,
    readdirSync: (p, o) => (o && o.withFileTypes ? [{ name: "@deepseek-ai", isSymbolicLink: () => true }] : fs.readdirSync(p, o)),
    renameSync: (a, b) => calls.rename.push([a, b]),
    rmSync: (a, o) => calls.rm.push([a, o]),
    existsSync: () => true,
    spawnSync: (cmd, args, opts) => {
      calls.spawnSync.push([cmd, args, opts]);
      return { status: 0 };
    },
    spawn: (cmd, args, opts) => {
      calls.spawn.push([cmd, args, opts]);
      const handlers = {};
      const child = {
        on: (ev, fn) => {
          handlers[ev] = fn;
        },
        kill: () => {},
      };
      setTimeout(() => handlers.exit && handlers.exit(state.exitCode), 0);
      return child;
    },
    homedir: () => "/home/test",
    installCommandFor: () => ({ command: "pnpm", args: ["add", "@huiliyi37/dsh-tianshu-tui@0.1.2-rc.30"], label: "pnpm add" }),
    detectPackageManager: () => "pnpm",
    process: { pid: 4321 },
  };
  const names = Object.keys(deps);
  const fn = new Function(...names, `${fnSrc}\nreturn installNpmVersion;`)(...names.map((n) => deps[n]));
  return { fn, calls };
}

{
  const state = { exitCode: 0 };
  const { fn, calls } = loadInstaller(state);
  let resolved = false;
  await fn("0.1.2-rc.30", PKG_DIR).then(() => {
    resolved = true;
  });
  ok(resolved, "a zero exit resolves the install");
  ok(calls.spawn.length === 1 && calls.spawn[0][0] === "pnpm" && calls.spawn[0][2].cwd === PKG_DIR, "pnpm runs in the profile dir");
  ok(calls.rename.length === 2 && calls.rename[0][0] === AI_DIR && calls.rename[0][1] === `${AI_DIR}.parked.4321`, "the @deepseek-ai symlink is parked before the install");
  ok(calls.rm.length === 1 && calls.rm[0][0] === AI_DIR, "whatever pnpm materialized is discarded");
  ok(calls.rename[1][0] === `${AI_DIR}.parked.4321` && calls.rename[1][1] === AI_DIR, "the parked symlink is restored afterwards");
  ok(calls.spawnSync.length === 1 && calls.spawnSync[0][0] === "/home/test/.local/bin/dsh-tui-repatch", "a successful install re-runs the translation patch");
}

{
  const state = { exitCode: 1 };
  const { fn, calls } = loadInstaller(state);
  let error = null;
  await fn("0.1.2-rc.30", PKG_DIR).catch((err) => {
    error = err;
  });
  ok(error !== null && String(error.message).includes("exited 1"), "a non-zero exit rejects");
  ok(calls.rename.length === 2, "the symlink is restored on the failure path too");
  ok(calls.spawnSync.length === 0, "no re-patch on a failed install");
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
