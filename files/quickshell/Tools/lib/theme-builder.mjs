import fs from 'node:fs';
import path from 'node:path';

function isPlainObject(val) {
  return val !== null && typeof val === 'object' && !Array.isArray(val);
}

function normalizeRel(partsDir, filePath) {
  const rel = path.relative(partsDir, filePath);
  return rel.split(path.sep).join('/');
}

const JSON_EXTENSIONS = new Set(['.json', '.jsonc']);

function stripJsonComments(input) {
  if (!input) return '';
  let str = String(input);
  if (str.charCodeAt(0) === 0xfeff) {
    str = str.slice(1);
  }
  let out = '';
  let inString = false;
  let escaped = false;
  let inSingleLine = false;
  let inMultiLine = false;
  for (let i = 0; i < str.length; i++) {
    const ch = str[i];
    const next = i + 1 < str.length ? str[i + 1] : '';
    if (inSingleLine) {
      if (ch === '\n' || ch === '\r') {
        inSingleLine = false;
        out += ch;
      }
      continue;
    }
    if (inMultiLine) {
      if (ch === '*' && next === '/') {
        inMultiLine = false;
        i++;
      }
      continue;
    }
    if (!inString && ch === '/' && next === '/') {
      inSingleLine = true;
      i++;
      continue;
    }
    if (!inString && ch === '/' && next === '*') {
      inMultiLine = true;
      i++;
      continue;
    }
    out += ch;
    if (inString) {
      if (!escaped && ch === '"') {
        inString = false;
      }
      escaped = !escaped && ch === '\\';
      continue;
    }
    if (ch === '"') {
      inString = true;
      escaped = false;
    }
  }
  return out;
}

function collectJsonFiles(dir) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  entries.sort((a, b) => a.name.localeCompare(b.name));
  const files = [];
  for (const entry of entries) {
    if (entry.name.startsWith('.')) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...collectJsonFiles(full));
    } else if (entry.isFile()) {
      const ext = path.extname(entry.name).toLowerCase();
      if (!JSON_EXTENSIONS.has(ext)) continue;
      if (entry.name === 'manifest.json') continue;
      if (entry.name === '.theme.json') continue;
      files.push(full);
    }
  }
  return files;
}

function readJson(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  try {
    const cleaned = stripJsonComments(raw);
    return JSON.parse(cleaned);
  } catch (err) {
    throw new Error(`Failed to parse JSON ${filePath}: ${err.message}`);
  }
}

function mergeInto(target, source, ctx, filePath, origins) {
  for (const [key, value] of Object.entries(source)) {
    const pathKey = ctx ? `${ctx}.${key}` : key;
    if (value === undefined) continue;
    if (!(key in target)) {
      target[key] = value;
      origins.set(pathKey, filePath);
      continue;
    }
    const existing = target[key];
    if (isPlainObject(existing) && isPlainObject(value)) {
      mergeInto(existing, value, pathKey, filePath, origins);
    } else {
      const prev = origins.get(pathKey) || '<unknown>';
      throw new Error(`Duplicate theme token at ${pathKey}: ${filePath} conflicts with ${prev}`);
    }
  }
}

export function loadThemeFromParts({ partsDir = 'Theme', allowEmpty = false } = {}) {
  const resolvedDir = path.resolve(partsDir);
  if (!fs.existsSync(resolvedDir)) {
    throw new Error(`Theme parts directory not found: ${resolvedDir}`);
  }
  let files = collectJsonFiles(resolvedDir);
  const manifestPath = path.join(resolvedDir, 'manifest.json');
  if (fs.existsSync(manifestPath)) {
    const raw = fs.readFileSync(manifestPath, 'utf8');
    let manifest = null;
    try {
      manifest = JSON.parse(stripJsonComments(raw));
    } catch (err) {
      throw new Error(`Invalid manifest ${manifestPath}: ${err.message}`);
    }
    if (!Array.isArray(manifest)) {
      throw new Error(`Theme manifest ${manifestPath} must be an array of relative file paths`);
    }
    const map = new Map(files.map(f => [normalizeRel(resolvedDir, f), f]));
    const ordered = [];
    for (const entry of manifest) {
      const rel = String(entry);
      const normalized = rel.replace(/\\/g, '/');
      if (!map.has(normalized)) {
        throw new Error(`Theme manifest entry ${rel} does not match any part under ${resolvedDir}`);
      }
      ordered.push(map.get(normalized));
      map.delete(normalized);
    }
    const remaining = Array.from(map.values()).sort((a, b) => a.localeCompare(b));
    files = [...ordered, ...remaining];
  }
  if (!files.length) {
    if (allowEmpty) return { theme: {}, files: [] };
    throw new Error(`Theme parts directory ${resolvedDir} has no JSON files`);
  }
  const theme = {};
  const origins = new Map();
  for (const file of files) {
    const obj = readJson(file);
    if (!isPlainObject(obj)) {
      throw new Error(`Theme part ${file} must be a JSON object at the top level`);
    }
    mergeInto(theme, obj, '', file, origins);
  }
  return { theme, files };
}

export function writeTheme(outPath, theme) {
  const resolved = path.resolve(outPath);
  const pretty = JSON.stringify(theme, null, 2) + '\n';
  fs.writeFileSync(resolved, pretty, 'utf8');
}

export { stripJsonComments };
