#!/usr/bin/env node
/**
 * dsh-startup-guard — composition duplicate-id heuristic patch (idempotent).
 *
 * Why: `compositionPreflight` concatenates the entry ids of every patch file
 * in the composed stack (the profile's `cordis.patch.yml` plus every bundle's
 * `dsh.bundle.patch`) and flags *any* repeat as
 * `duplicate entry id "X" ... (loader-level boot failure)`.
 *
 * On dsh 0.1.5 that is a false positive for the normal layering mechanism:
 * a later layer re-declares an earlier layer's id to override it. Upstream's
 * own bundles do it (`@deepseek-ai/dsh-base` and `@deepseek-ai/dsh-web-app`
 * both ship `tool-bash`, `tools`, `system-prompt`, ...), the profile patch
 * overrides base rows (`web-runtime`, `agent-presets`, ...), and aggregate
 * bundles re-declare their sub-plugin rows (`@linxin666/dsh-web-ui-all`).
 * The tree boots clean with all of them, so the guard reported 37 issues for
 * the web profile and 1 for the tui profile on every run.
 *
 * What this changes: a repeated id is only flagged when it repeats within the
 * *same* patch file — a real authoring bug. Cross-file re-declaration is the
 * documented override mechanism. All other fatal-shape checks (tab
 * indentation, empty insert, top-level non-list content) and the
 * `duplicate entry id` issue shape stay intact, so `isFatalShape` in strict
 * mode still blocks genuine same-file duplicates.
 *
 * Idempotent: a sentinel comment marks the patched file. If the anchors are
 * not found (a guard upgrade rewrote the function), the file is left
 * untouched and the patcher exits non-zero with a drift message.
 *
 * Usage: node guard-patch.mjs <path/to/guard-core.mjs>
 */
import fs from "node:fs";
import crypto from "node:crypto";
import { execFileSync } from "node:child_process";

const SENTINEL = "// dsh-guard-patch:per-source-duplicate-ids";

function log(msg) {
  console.error(`[dsh-guard-patch] ${msg}`);
}

const core = process.argv[2];
if (!core) {
  log("usage: node guard-patch.mjs <path/to/guard-core.mjs>");
  process.exit(2);
}

let src;
try {
  src = fs.readFileSync(core, "utf8");
} catch (error) {
  log(`cannot read ${core}: ${error.message}`);
  process.exit(1);
}

if (src.includes(SENTINEL)) {
  log(`already patched: ${core}`);
  process.exit(0);
}

const A_ORIG = [
  "  const allIds = [];",
  "  const allNames = [];",
].join("\n");
const A_REPL = [
  "  const allIds = [];",
  `  ${SENTINEL}`,
  "  const idSources = []; // [id, patch file]; a repeat is only a bug within one file",
  "  const allNames = [];",
].join("\n");

const B_ORIG = [
  "    issues.push(...r.issues);",
  "    allIds.push(...r.ids);",
  "    for (const n of r.names) allNames.push({ name: n, baseDir: profileDir });",
].join("\n");
const B_REPL = [
  "    issues.push(...r.issues);",
  "    allIds.push(...r.ids);",
  "    idSources.push(...r.ids.map((id) => [id, `${basename(profileDir)}/cordis.patch.yml`]));",
  "    for (const n of r.names) allNames.push({ name: n, baseDir: profileDir });",
].join("\n");

const C_ORIG = [
  "    issues.push(...r.issues);",
  "    allIds.push(...r.ids);",
  "    for (const n of r.names) allNames.push({ name: n, baseDir: dirname(patchPath) });",
].join("\n");
const C_REPL = [
  "    issues.push(...r.issues);",
  "    allIds.push(...r.ids);",
  "    idSources.push(...r.ids.map((id) => [id, `${bundle}/cordis.patch.yml`]));",
  "    for (const n of r.names) allNames.push({ name: n, baseDir: dirname(patchPath) });",
].join("\n");

const D_ORIG = [
  "  const seen = new Map();",
  "  for (const id of allIds) {",
  "    if (seen.has(id)) {",
  '      if (seen.get(id) === 1) issues.push(`duplicate entry id "${id}" in the composed patch stack (loader-level boot failure)`);',
  "      seen.set(id, seen.get(id) + 1);",
  "    } else seen.set(id, 1);",
  "  }",
].join("\n");
const D_REPL = [
  "  const seen = new Map();",
  "  for (const [id, source] of idSources) {",
  "    const key = JSON.stringify([source, id]);",
  "    if (seen.has(key)) {",
  '      if (seen.get(key) === 1) issues.push(`duplicate entry id "${id}" in ${source} (loader-level boot failure)`);',
  "      seen.set(key, seen.get(key) + 1);",
  "    } else seen.set(key, 1);",
  "  }",
].join("\n");

const edits = [
  ["allIds declaration", A_ORIG, A_REPL],
  ["profile-branch id collection", B_ORIG, B_REPL],
  ["bundle-branch id collection", C_ORIG, C_REPL],
  ["duplicate-id loop", D_ORIG, D_REPL],
];

for (const [label, orig] of edits) {
  const count = src.split(orig).length - 1;
  if (count !== 1) {
    log(`${label}: expected 1 anchor, found ${count} — guard version drift, leaving ${core} untouched`);
    process.exit(1);
  }
}

for (const [, orig, repl] of edits) {
  src = src.replace(orig, repl);
}

const tmp = `${core}.dsh-guard-patch.tmp.mjs`;
try {
  fs.writeFileSync(tmp, src);
  // Validate the patched ESM before touching the live file.
  execFileSync(process.execPath, ["--check", tmp], { stdio: ["ignore", "ignore", "pipe"] });
} catch (error) {
  try { fs.rmSync(tmp, { force: true }); } catch { /* best effort */ }
  log(`patched file failed validation: ${(error && error.stderr ? error.stderr.toString() : error.message).trim()}`);
  process.exit(1);
}

try {
  if (!fs.existsSync(`${core}.orig`)) {
    fs.copyFileSync(core, `${core}.orig`);
  }
  const sha = crypto.createHash("sha256").update(src).digest("hex");
  fs.renameSync(tmp, core);
  fs.writeFileSync(
    `${core}.dsh-guard-patch.json`,
    JSON.stringify({ patchedAt: new Date().toISOString(), sha256: sha }, null, 2),
  );
} catch (error) {
  try { fs.rmSync(tmp, { force: true }); } catch { /* best effort */ }
  log(`cannot write ${core}: ${error.message}`);
  process.exit(1);
}

log(`patched: ${core}`);
