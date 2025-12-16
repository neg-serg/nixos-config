#!/usr/bin/env node
/**
 * validate-settings.mjs — Validate Settings.json against Docs/SettingsSchema.json
 *
 * Usage:
 *   node Tools/validate-settings.mjs [--settings ~/.config/quickshell/Settings.json] [--schema Docs/SettingsSchema.json]
 *
 * Validates basic JSON Schema (Draft-07 subset):
 * - type: object, array, string, integer, number, boolean
 * - enum
 * - minimum / maximum (number/integer)
 * - items (single schema) for arrays
 * - properties for objects (does not enforce "required")
 * - additionalProperties (true/false or schema) — if false, flags unknown keys
 */
import fs from 'node:fs';
import path from 'node:path';

function parseArgs(argv) {
  const args = { settings: path.join(process.env.HOME || '', '.config/quickshell/Settings.json'), schema: 'Docs/SettingsSchema.json' };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--settings') { args.settings = argv[++i]; continue; }
    if (a === '--schema') { args.schema = argv[++i]; continue; }
  }
  return args;
}

function readJson(p) {
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); }
  catch (e) { console.error('ERR: read JSON', p, e.message); process.exit(2); }
}

function typeOf(x) {
  if (x === null) return 'null';
  if (Array.isArray(x)) return 'array';
  return typeof x; // object, number, string, boolean
}

function validate(value, schema, ctx, errors) {
  const here = ctx || '';
  // Handle simple boolean schemas (not used, but keep for completeness)
  if (schema === true) return;
  if (schema === false) { errors.push(`${here}: value not allowed by schema`); return; }

  const t = schema.type;
  if (t) {
    const vt = typeOf(value);
    if (t === 'integer') {
      if (!(vt === 'number' && Number.isInteger(value))) {
        errors.push(`${here}: expected integer, got ${vt}`);
        return; // further numeric checks meaningless
      }
    } else if (t === 'number') {
      if (vt !== 'number' || !Number.isFinite(value)) {
        errors.push(`${here}: expected number, got ${vt}`);
        return;
      }
    } else if (t === 'array') {
      if (vt !== 'array') { errors.push(`${here}: expected array, got ${vt}`); return; }
      if (schema.items) {
        for (let i = 0; i < value.length; i++) {
          validate(value[i], schema.items, `${here}[${i}]`, errors);
        }
      }
      return; // arrays have no further checks here
    } else if (t === 'object') {
      if (vt !== 'object') { errors.push(`${here}: expected object, got ${vt}`); return; }
      const props = schema.properties || {};
      const addl = schema.additionalProperties;
      // Properties validation
      for (const k of Object.keys(value)) {
        if (Object.prototype.hasOwnProperty.call(props, k)) {
          validate(value[k], props[k], `${here ? here + '.' : ''}${k}`, errors);
        } else if (addl === false) {
          errors.push(`${here}: unknown property '${k}'`);
        } else if (addl && typeof addl === 'object') {
          validate(value[k], addl, `${here ? here + '.' : ''}${k}`, errors);
        }
      }
      // No required enforcement; defaults are applied by runtime
      return;
    } else {
      if (vt !== t) { errors.push(`${here}: expected ${t}, got ${vt}`); return; }
    }
  }

  if (schema.enum) {
    if (!schema.enum.some(v => v === value)) {
      errors.push(`${here}: value '${value}' not in enum [${schema.enum.join(', ')}]`);
      return;
    }
  }

  if ((schema.type === 'number' || schema.type === 'integer') && typeof value === 'number' && Number.isFinite(value)) {
    if (schema.minimum !== undefined && value < schema.minimum) {
      errors.push(`${here}: ${value} < minimum ${schema.minimum}`);
    }
    if (schema.maximum !== undefined && value > schema.maximum) {
      errors.push(`${here}: ${value} > maximum ${schema.maximum}`);
    }
  }
}

function main() {
  const args = parseArgs(process.argv);
  const settingsPath = path.resolve(process.cwd(), args.settings);
  const schemaPath = path.resolve(process.cwd(), args.schema);
  const settings = readJson(settingsPath);
  const schema = readJson(schemaPath);

  const errors = [];
  validate(settings, schema, 'root', errors);

  if (errors.length) {
    console.log(`Validate: ${path.relative(process.cwd(), settingsPath)} against ${path.relative(process.cwd(), schemaPath)}`);
    for (const e of errors) console.error(' -', e);
    console.error(`\nValidation failed: ${errors.length} error(s).`);
    process.exitCode = 1;
  }
}

main();
