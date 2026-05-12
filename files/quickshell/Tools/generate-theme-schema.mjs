#!/usr/bin/env node
// Generate Docs/ThemeHierarchical.json from Theme parts (fallback to Theme/.theme.json)
import fs from 'node:fs';
import path from 'node:path';
import { loadThemeFromParts, writeTheme } from './lib/theme-builder.mjs';

const root = process.cwd();
const partsDir = path.resolve(root, 'Theme');
const themePath = path.resolve(root, 'Theme/.theme.json');
const outPath = path.resolve(root, 'Docs/ThemeHierarchical.json');

try {
  let theme = null;
  if (fs.existsSync(partsDir)) {
    ({ theme } = loadThemeFromParts({ partsDir }));
  } else {
    const s = fs.readFileSync(themePath, 'utf8');
    theme = JSON.parse(s);
  }
  writeTheme(outPath, theme);
  const source = fs.existsSync(partsDir) ? path.relative(root, partsDir) : path.relative(root, themePath);
  console.log('Wrote', path.relative(root, outPath), 'from', source);
} catch (e) {
  console.error('Failed to generate schema:', e.message);
  process.exitCode = 1;
}
