#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const cfgDir = root; // quickshell/.config/quickshell
const settingsQml = path.join(root, 'Settings/Settings.qml');

function read(p) { return fs.readFileSync(p, 'utf8'); }

function walkFiles(dir, exts, acc = []) {
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    if (ent.name === 'vendor' || ent.name === 'node_modules' || ent.name === '.git') continue;
    const p = path.join(dir, ent.name);
    if (ent.isDirectory()) walkFiles(p, exts, acc); else {
      const ext = path.extname(ent.name).toLowerCase();
      if (exts.has(ext)) acc.push(p);
    }
  }
  return acc;
}

function parseDefinedSettingsKeys(qmlSource) {
  const start = qmlSource.indexOf('JsonAdapter');
  if (start === -1) return [];
  // crude brace tracking from first '{' after 'JsonAdapter'
  const open = qmlSource.indexOf('{', start);
  let i = open + 1, depth = 1; const body = [];
  while (i < qmlSource.length && depth > 0) {
    const ch = qmlSource[i];
    body.push(ch);
    if (ch === '{') depth++; else if (ch === '}') depth--;
    i++;
  }
  const seg = body.join('');
  const re = /\bproperty\s+\w+\s+([A-Za-z0-9_]+)\s*:/g;
  const keys = new Set(); let m;
  while ((m = re.exec(seg)) !== null) keys.add(m[1]);
  return Array.from(keys);
}

function parseUsedSettingsKeys(files) {
  const re = /Settings\.settings\.([A-Za-z0-9_]+)/g;
  const keys = new Set();
  for (const f of files) {
    const s = read(f);
    let m; while ((m = re.exec(s)) !== null) keys.add(m[1]);
  }
  return Array.from(keys);
}

function main() {
  const exts = new Set(['.qml', '.js', '.mjs']);
  const files = walkFiles(cfgDir, exts, []);
  const def = new Set(parseDefinedSettingsKeys(read(settingsQml)));
  const used = new Set(parseUsedSettingsKeys(files));
  const unused = Array.from(def).filter(k => !used.has(k)).sort();
  const unknown = Array.from(used).filter(k => !def.has(k)).sort();

  if (unknown.length) {
    console.error('\nUnknown Settings keys (used but not defined in JsonAdapter):');
    for (const k of unknown) console.error(' -', k);
  }

  if (unused.length) {
    console.log('\nUnused Settings keys (defined but never used):');
    for (const k of unused) console.log(' -', k);
  }

  if (unknown.length) process.exit(1);
}

main();
