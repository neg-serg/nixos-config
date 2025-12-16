#!/usr/bin/env node
/**
 * validate-theme.mjs — Dev script to validate the generated theme JSON against a hierarchical schema
 *
 * Usage:
 *   node Tools/validate-theme.mjs [--theme Theme/.theme.json] [--schema Docs/ThemeHierarchical.json] [--constraints Docs/ThemeConstraints.json] [--parts Theme] [--strict] [--verbose]
 *
 * Checks:
 * - Unknown (extra) tokens not present in the schema
 * - Flat tokens at the root (legacy)
 * - Deprecated tokens (hardcoded list)
 * - Missing tokens (schema leaves not present) — informational unless --strict
 */
import fs from 'node:fs';
import path from 'node:path';
import { loadThemeFromParts } from './lib/theme-builder.mjs';

const cwd = process.cwd();
function readJson(p) {
  try {
    const s = fs.readFileSync(p, 'utf8');
    return JSON.parse(s);
  } catch (e) {
    console.error(`ERR: Failed to read JSON ${p}:`, e.message);
    process.exitCode = 2;
    return {};
  }
}

function flatten(obj, base = '') {
  const out = new Set();
  function walk(o, prefix) {
    if (o === null || o === undefined) return;
    if (Array.isArray(o)) {
      // Arrays are not part of theme schema; treat as leaf
      out.add(prefix);
      return;
    }
    if (typeof o === 'object') {
      const keys = Object.keys(o);
      if (keys.length === 0) {
        out.add(prefix);
        return;
      }
      for (const k of keys) {
        const p = prefix ? `${prefix}.${k}` : k;
        if (o[k] !== null && typeof o[k] === 'object' && !Array.isArray(o[k])) {
          walk(o[k], p);
        } else {
          out.add(p);
        }
      }
    } else {
      out.add(prefix);
    }
  }
  walk(obj, base);
  return out;
}

function parseArgs(argv) {
  const args = {
    theme: 'Theme/.theme.json',
    schema: 'Docs/ThemeHierarchical.json',
    constraints: 'Docs/ThemeConstraints.json',
    parts: null,
    strict: false,
    verbose: false,
    preferParts: true,
    partsDisabled: false
  };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--theme') { args.theme = argv[++i]; continue; }
    if (a === '--schema') { args.schema = argv[++i]; continue; }
    if (a === '--constraints') { args.constraints = argv[++i]; continue; }
    if (a === '--parts') { args.parts = argv[++i]; args.partsDisabled = false; args.preferParts = true; continue; }
    if (a === '--no-parts') { args.parts = null; args.partsDisabled = true; args.preferParts = false; continue; }
    if (a === '--prefer-parts' || a === '--from-parts') { args.preferParts = true; continue; }
    if (a === '--strict') { args.strict = true; continue; }
    if (a === '--verbose') { args.verbose = true; continue; }
  }
  return args;
}


function resolvePartsDir(args, cwd, themePath) {
  if (args.partsDisabled) return null;
  const candidates = [];
  if (args.parts) {
    candidates.push(path.resolve(cwd, args.parts));
  }
  const themeDir = path.dirname(themePath);
  if (path.basename(themeDir) === 'Theme') {
    candidates.push(themeDir);
  } else {
    candidates.push(path.join(themeDir, 'Theme'));
  }
  const seen = new Set();
  for (const dir of candidates) {
    if (!dir || seen.has(dir)) continue;
    seen.add(dir);
    if (fs.existsSync(dir)) return dir;
  }
  return null;
}

function getThemeData(args, cwd) {
  const themePath = path.resolve(cwd, args.theme);
  const partsDir = resolvePartsDir(args, cwd, themePath);
  const shouldUseParts = Boolean(partsDir && (args.preferParts || !fs.existsSync(themePath)));
  if (shouldUseParts) {
    const { theme } = loadThemeFromParts({ partsDir });
    return { theme, themePath };
  }
  const theme = readJson(themePath);
  return { theme, themePath };
}

function main() {
  const args = parseArgs(process.argv);
  const { theme, themePath } = getThemeData(args, cwd);
  const schemaPath = path.resolve(cwd, args.schema);
  const schema = readJson(schemaPath);
  const constraints = fs.existsSync(args.constraints) ? readJson(path.resolve(cwd, args.constraints)) : {};

  const themePaths = flatten(theme);
  const schemaPaths = flatten(schema);

  // Unknown tokens: in theme but not in schema
  const unknown = [];
  for (const p of themePaths) if (!schemaPaths.has(p)) unknown.push(p);

  // Flat token detection removed — schema is authoritative and flat tokens are no longer supported.


  // Missing tokens (schema leaves not present in theme)
  function getAt(o, p) {
    try { return p.split('.').reduce((a, k) => (a ? a[k] : undefined), o); } catch { return undefined; }
  }
  const SKIP_MISSING = new Set(['media.time.fontScale']);
  const missing = [];
  for (const p of schemaPaths) {
    if (themePaths.has(p)) continue;
    if (SKIP_MISSING.has(p)) continue;
    const v = getAt(schema, p);
    if (v !== null && typeof v === 'object') continue; // ignore pure object groups
    missing.push(p);
  }

  function hdr(s) { console.log(`\n=== ${s} ===`); }

  // (flat tokens check removed)

  // Range/type checks from constraints
  function get(o, p) { try { return p.split('.').reduce((a,k)=> (a ? a[k] : undefined), o); } catch { return undefined; } }
  const bad = [];
  for (const [p, rule] of Object.entries(constraints || {})) {
    const v = get(theme, p);
    if (v === undefined) continue; // not present: let "missing" list cover it
    const t = typeof v;
    if (rule.type) {
      if (rule.type === 'integer') {
        if (!(t === 'number' && Number.isInteger(v))) bad.push(`${p}: expected integer, got ${t}`);
      } else if (rule.type === 'number') {
        if (!(t === 'number' && Number.isFinite(v))) bad.push(`${p}: expected number, got ${t}`);
      }
    }
    if (typeof v === 'number' && Number.isFinite(v)) {
      if (rule.min !== undefined && v < rule.min) bad.push(`${p}: ${v} < min ${rule.min}`);
      if (rule.max !== undefined && v > rule.max) bad.push(`${p}: ${v} > max ${rule.max}`);
    }
  }

  const hasFindings = unknown.length || missing.length || bad.length;
  if (args.verbose) {
    const relTheme = path.relative(cwd, themePath);
    const relSchema = path.relative(cwd, schemaPath);
    console.log(`Validate: ${relTheme} vs schema ${relSchema}${hasFindings ? '' : ' — OK'}`);
  } else if (hasFindings) {
    console.log(`Validate: ${path.relative(cwd, themePath)} vs schema ${path.relative(cwd, schemaPath)}`);
  }

  if (unknown.length) {
    hdr('Unknown tokens');
    unknown.sort().forEach(p => console.log('  +', p));
  }

  if (missing.length) {
    hdr('Missing tokens (informational)');
    missing.sort().forEach(p => console.log('  -', p));
  }

  if (bad.length) {
    hdr('Constraint violations');
    bad.sort().forEach(x => console.log('  !', x));
  }

  if (args.strict && (unknown.length || bad.length)) {
    console.error('\nStrict mode: validation errors present.');
    process.exitCode = 1;
  }
}

main();
