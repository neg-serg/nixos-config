#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadThemeFromParts } from './lib/theme-builder.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const themeJson = path.join(root, 'Theme/.theme.json');
const themeQml = path.join(root, 'Settings/Theme.qml');

function read(p){ return fs.readFileSync(p,'utf8'); }

function flatten(obj, base = '') {
  const out = new Set();
  function walk(o, prefix) {
    if (o && typeof o === 'object' && !Array.isArray(o)) {
      const keys = Object.keys(o);
      if (keys.length === 0) { if (prefix) out.add(prefix); return; }
      for (const k of keys) walk(o[k], prefix ? `${prefix}.${k}` : k);
    } else { if (prefix) out.add(prefix); }
  }
  walk(obj, base);
  return Array.from(out);
}

// Tokens that Settings/Theme.qml reads with a fallback and that are absent from
// the parts on purpose:
// - colors.overrides.* — override slots for the derived colors; a theme that
//   wants different formulas adds them (ThemeParts.js warnMissingToken() skips
//   them too, so strict mode stays quiet).
// - network.capsule.* — inherit keyboard.capsule.* while absent; a concrete
//   value in network.jsonc would freeze that inheritance.
const OPTIONAL_TOKEN_PATTERNS = [
  /^colors\.overrides\./,
  /^network\.capsule\.(iconSpacing|iconScale|iconBaselineOffset|labelPadding|minLabelGap|iconAlignMode)$/,
];
const isOptionalToken = p => OPTIONAL_TOKEN_PATTERNS.some(re => re.test(p));

function main(){
  let theme = null;
  const partsDir = path.join(root, 'Theme');
  if (fs.existsSync(partsDir)) {
    ({ theme } = loadThemeFromParts({ partsDir }));
  } else {
    theme = JSON.parse(read(themeJson));
  }
  const qml = read(themeQml);
  const def = new Set(flatten(theme));
  const re = /val\('([^']+)'/g;
  const used = new Set();
  let m; while ((m = re.exec(qml)) !== null) used.add(m[1]);

  // Greeter tokens are consumed by greeter/GreeterTheme.qml, outside this file.
  const unused = Array.from(def).filter(p => !used.has(p) && !/^greeter\./.test(p)).sort();
  const unknown = Array.from(used).filter(p => !def.has(p) && !isOptionalToken(p)).sort();

  if (unknown.length) {
    console.error('\nUnknown Theme tokens (used in Theme.qml but not present in Theme/.theme.json):');
    for (const p of unknown) console.error(' -', p);
  } else {
    console.log('No unknown Theme tokens.');
  }

  if (unused.length) {
    console.log('\nUnused Theme tokens (present in Theme/.theme.json but not referenced in Theme.qml):');
    for (const p of unused) console.log(' -', p);
  } else {
    console.log('No unused Theme tokens.');
  }

  if (unknown.length) process.exit(1);
}

main();
