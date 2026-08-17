#!/usr/bin/env node
/**
 * dsh web profile — English UI copy patcher (idempotent).
 *
 * The web profile's third-party plugin bundles hardcode Chinese UI strings
 * (spotlight palette titles/tooltips, free-search settings labels, plugin
 * vetting report, file-upload truncation notices) that ignore the dsh locale
 * preference. This patcher swaps the exact string literals listed in the
 * translation map (i18n.json) for English ones, in place, after verifying
 * each key actually occurs.
 *
 * Usage: node patch.mjs <i18n.json> <profile-node_modules-dir>
 *
 * Safety:
 *  - idempotent: a marker file (.dsh-web-en.json next to each bundle) records
 *    the map + bundle hashes, so already-patched bundles are skipped;
 *  - keys that do not occur in this bundle version are skipped with a warning
 *    (the map may cover a slightly different version);
 *  - if any applied key is still present after replacement, the bundle is
 *    left untouched and the patcher exits non-zero;
 *  - the pristine bundle is backed up once as <file>.orig.
 */
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

function log(msg) {
  console.error(`[dsh-web-en] ${msg}`);
}

const [mapPath, profileDir] = process.argv.slice(2);
if (!mapPath || !profileDir) {
  log("usage: node patch.mjs <i18n.json> <profile-node_modules-dir>");
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

let failures = 0;

for (const [relPath, table] of Object.entries(map)) {
  const bundlePath = path.join(profileDir, relPath);
  if (!fs.existsSync(bundlePath)) {
    log(`skip (absent): ${relPath}`);
    continue;
  }
  const pkgDir = path.resolve(path.dirname(bundlePath), "..");
  // Per-bundle marker (a package may host several patched bundles, e.g. the
  // dsh-plugin-vetting lib files — a single per-package marker would be
  // overwritten by the last-processed file and re-patch the others every run).
  const markerPath = `${bundlePath}.web-en.json`;
  const origPath = `${bundlePath}.orig`;

  let bundle;
  try {
    bundle = fs.readFileSync(bundlePath, "utf8");
  } catch (e) {
    log(`cannot read bundle: ${e.message}`);
    failures++;
    continue;
  }

  // Already patched with this exact map on this exact bundle?
  let marker = null;
  try {
    marker = JSON.parse(fs.readFileSync(markerPath, "utf8"));
  } catch {}
  const origBundleSha = crypto.createHash("sha256").update(bundle).digest("hex");
  if (marker && marker.mapSha === mapSha && marker.bundleSha === origBundleSha) {
    log(`up to date: ${relPath}`);
    continue;
  }

  // Apply replacements longest-first (so overlapping literals stay consistent).
  const entries = Object.entries(table).sort((a, b) => b[0].length - a[0].length);
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
    log(`verification failed: ${relPath} — ${leftovers.length} keys still present, bundle NOT modified`);
    for (const k of leftovers.slice(0, 5)) log(`  still present: ${JSON.stringify(k)}`);
    failures++;
    continue;
  }

  // First-time backup of the pristine bundle.
  if (!fs.existsSync(origPath)) {
    fs.writeFileSync(origPath, fs.readFileSync(bundlePath));
    log(`backup written: ${origPath}`);
  }

  // Atomic write + marker. The marker's bundle hash covers the PATCHED
  // content, so a later run sees the file as up to date (bundleSha is only
  // meaningful as "this exact content was already patched with this map").
  const patchedSha = crypto.createHash("sha256").update(bundle).digest("hex");
  const tmpPath = `${bundlePath}.en-tmp`;
  fs.writeFileSync(tmpPath, bundle);
  fs.renameSync(tmpPath, bundlePath);
  fs.writeFileSync(
    markerPath,
    `${JSON.stringify(
      {
        mapSha,
        bundleSha: patchedSha,
        at: new Date().toISOString(),
        stringsApplied: applied,
      },
      null,
      2
    )}\n`
  );

  log(`patched ${relPath}: ${applied} strings replaced, ${missing.length} not present in this version`);
}

process.exit(failures ? 1 : 0);
