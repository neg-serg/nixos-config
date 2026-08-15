#!/usr/bin/env node
/**
 * dsh-tianshu-tui — Russian UI patch (idempotent).
 *
 * The Tianshu TUI bundle (`@huiliyi37/dsh-tianshu-tui`) hardcodes its UI
 * strings in Chinese with no language switch. This patcher swaps the exact
 * string literals listed in the translation map (i18n.json) for Russian
 * ones, in place, after verifying each key actually occurs.
 *
 * Usage: node patch.mjs <i18n.json> <bundle-lib/index.js>
 *
 * Safety:
 *  - idempotent: a marker file (.dsh-tui-ru.json next to the package) records
 *    the map + bundle hashes, so already-patched bundles are skipped;
 *  - keys that do not occur in this bundle version are skipped with a warning
 *    (the map may cover a slightly different version);
 *  - if any applied key is still present after replacement, the bundle is
 *    left untouched and the patcher exits non-zero;
 *  - the pristine bundle is backed up once as index.js.orig.
 */
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

function log(msg) {
  console.error(`[dsh-tui-ru] ${msg}`);
}

const [mapPath, bundlePath] = process.argv.slice(2);
if (!mapPath || !bundlePath) {
  log("usage: node patch.mjs <i18n.json> <bundle-lib/index.js>");
  process.exit(2);
}

const mapRaw = fs.readFileSync(mapPath, "utf8");
let map;
try {
  map = JSON.parse(mapRaw);
} catch (e) {
  log(`cannot parse translation map: ${e.message}`);
  process.exit(1);
}
const mapSha = crypto.createHash("sha256").update(mapRaw).digest("hex");

const pkgDir = path.resolve(path.dirname(bundlePath), "..");
const markerPath = path.join(pkgDir, ".dsh-tui-ru.json");
const origPath = `${bundlePath}.orig`;

let bundle;
try {
  bundle = fs.readFileSync(bundlePath, "utf8");
} catch (e) {
  log(`cannot read bundle: ${e.message}`);
  process.exit(1);
}
const bundleSha = crypto.createHash("sha256").update(bundle).digest("hex");

// Already patched with this exact map on this exact bundle?
let marker = null;
try {
  marker = JSON.parse(fs.readFileSync(markerPath, "utf8"));
} catch {}
if (marker && marker.mapSha === mapSha && marker.bundleSha === bundleSha) {
  log(`up to date: ${bundlePath}`);
  process.exit(0);
}

// Apply replacements longest-first (so overlapping literals stay consistent).
const entries = Object.entries(map).sort((a, b) => b[0].length - a[0].length);
const missing = [];
let applied = 0;
for (const [k, v] of entries) {
  if (!bundle.includes(k)) {
    missing.push(k);
    continue;
  }
  bundle = bundle.split(k).join(v);
  applied++;
}

// Verification: no applied key may remain.
const leftovers = entries.filter(([k]) => bundle.includes(k)).map(([k]) => k);
if (leftovers.length) {
  log(`verification failed: ${leftovers.length} keys still present — bundle NOT modified`);
  for (const k of leftovers.slice(0, 5)) log(`  still present: ${JSON.stringify(k)}`);
  process.exit(1);
}

// First-time backup of the pristine bundle.
if (!fs.existsSync(origPath)) {
  fs.writeFileSync(origPath, fs.readFileSync(bundlePath));
  log(`backup written: ${origPath}`);
}

// Atomic write + marker.
const tmpPath = `${bundlePath}.ru-tmp`;
fs.writeFileSync(tmpPath, bundle);
fs.renameSync(tmpPath, bundlePath);
fs.writeFileSync(
  markerPath,
  `${JSON.stringify(
    {
      mapSha,
      bundleSha,
      at: new Date().toISOString(),
      stringsApplied: applied,
    },
    null,
    2
  )}\n`
);

log(`patched ${bundlePath}: ${applied} strings replaced, ${missing.length} not present in this version (covered by longer entries or plugin-version drift)`);
process.exit(0);
