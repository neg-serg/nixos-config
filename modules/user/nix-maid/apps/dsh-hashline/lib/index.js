/**
 * dsh-hashline — hash-anchored file reads/edits for the dsh web profile.
 *
 * Companion tools to the built-in read/write/edit family:
 *   read_hashline — reads a file and tags every line with a LINE#ID anchor
 *                   ('N#ID| text'); the ID is a 2-char content hash.
 *   hashline_edit — applies replace/append/prepend ops whose line references
 *                   carry expected hashes; before writing it re-reads the file
 *                   and recomputes every referenced hash, so stale edits are
 *                   rejected instead of corrupting the file.
 *
 * Hash input: CR stripped, trailing whitespace trimmed; blank lines hash the
 * 1-based line number so they stay position-dependent. The hash is xxHash32
 * when the runtime's node:crypto supports it, otherwise FNV-1a 32-bit; the
 * value is reduced modulo 256 and mapped to two chars of a 16-symbol nibble
 * alphabet (ZPMQVRWSNKTXJBYH), matching the omo hashline design.
 *
 * @module dsh-hashline
 */

import { createHash } from 'node:crypto'
import { readFile, rename, rm, writeFile } from 'node:fs/promises'
import { isAbsolute, resolve } from 'node:path'
import { defineTool } from '@deepseek-ai/dsh-tools'

/** Cordis plugin name — must match the patch row / package name. */
export const name = 'dsh-hashline'

/** Required services: the tool registry. */
export const inject = ['tools']

// ---------------------------------------------------------------------------
// hashing
// ---------------------------------------------------------------------------

const NIBBLE_STR = 'ZPMQVRWSNKTXJBYH'

/** True when node:crypto exposes the xxhash32 digest (OpenSSL 3 + new Node). */
const XXHASH32_AVAILABLE = (() => {
  try {
    createHash('xxhash32')
    return true
  } catch {
    return false
  }
})()

/** FNV-1a 32-bit over the UTF-8 bytes of input. */
function fnv1a32(input) {
  const bytes = new TextEncoder().encode(input)
  let hash = 0x811c9dc5
  for (let i = 0; i < bytes.length; i += 1) {
    hash ^= bytes[i]
    hash = Math.imul(hash, 0x01000193)
    hash >>>= 0
  }
  return hash
}

/**
 * Two-char LINE#ID tag body for one line.
 * Normalization: CR stripped, trailing whitespace trimmed. A blank line hashes
 * its 1-based line number instead of the empty string, so blank lines stay
 * distinguishable and position-dependent.
 */
function lineHash(line, lineNumber) {
  const normalized = line.replace(/\r/g, '').trimEnd()
  const input = normalized === '' ? String(lineNumber) : normalized
  let value
  if (XXHASH32_AVAILABLE) {
    value = createHash('xxhash32').update(input, 'utf8').digest().readUInt32BE(0)
  } else {
    value = fnv1a32(input)
  }
  const index = value % 256
  return NIBBLE_STR[Math.floor(index / 16)] + NIBBLE_STR[index % 16]
}

// ---------------------------------------------------------------------------
// file text helpers
// ---------------------------------------------------------------------------

/** Split file text into lines, remembering EOL style and a trailing newline. */
function splitLines(content) {
  const eol = content.includes('\r\n') ? '\r\n' : '\n'
  let lines = content.split(/\r?\n/)
  const endsWithNewline = lines.length > 1 && lines[lines.length - 1] === ''
  if (endsWithNewline) lines = lines.slice(0, -1)
  return { lines, eol, endsWithNewline }
}

/** Rejoin lines preserving the original EOL style and trailing newline. */
function joinLines(lines, eol, endsWithNewline) {
  let text = lines.join(eol)
  if (endsWithNewline) text += eol
  return text
}

/**
 * Resolve a possibly-relative path: session workspace cwd (as carried on the
 * execution context), falling back to the process cwd for non-agent callers.
 */
function resolvePath(rawPath, exec) {
  if (isAbsolute(rawPath)) return rawPath
  const sessionCwd =
    exec && exec.agent && exec.agent.session && exec.agent.session.header
      ? exec.agent.session.header.cwd
      : undefined
  const base = typeof sessionCwd === 'string' && sessionCwd !== '' ? sessionCwd : process.cwd()
  return resolve(base, rawPath)
}

// ---------------------------------------------------------------------------
// read_hashline
// ---------------------------------------------------------------------------

const readHashlineTool = defineTool({
  name: 'read_hashline',
  description:
    'Read a file and tag each line with a LINE#ID content-hash anchor: every line is rendered as '
    + 'N#ID| text, where N is the 1-based line number and ID is a 2-character hash of that line '
    + 'content (trailing whitespace ignored; blank lines hash the line number). Pass the N#ID '
    + 'anchors back to hashline_edit so stale edits are rejected when the file changed between read '
    + 'and edit. Use offset/limit to read a window; line numbers always refer to the whole file.',
  parameters: {
    path: {
      type: 'string',
      required: true,
      description: 'Path to the file to read; relative paths resolve against the session workspace.',
    },
    offset: {
      type: 'integer',
      description: '1-based first line to return (default 1).',
    },
    limit: {
      type: 'integer',
      description: 'Maximum number of lines to return (default: all remaining lines).',
    },
  },
  output: {
    schema: { type: 'string' },
    render: (_args, value) => [{ type: 'text', text: value }],
  },
  isConcurrencySafe: () => true,
  timeoutMs: 30_000,
  async execute(args, exec) {
    const filePath = resolvePath(args.path, exec)
    const content = await readFile(filePath, 'utf8')
    const { lines } = splitLines(content)
    if (lines.length === 0) return ''
    const offset = args.offset === undefined ? 1 : args.offset
    const limit = args.limit === undefined ? lines.length : args.limit
    if (!Number.isInteger(offset) || offset < 1) {
      throw new Error('read_hashline: offset must be a positive integer')
    }
    if (!Number.isInteger(limit) || limit < 1) {
      throw new Error('read_hashline: limit must be a positive integer')
    }
    if (offset > lines.length) {
      throw new Error('read_hashline: offset ' + offset + ' is out of range for "' + filePath
        + '" (' + lines.length + ' lines)')
    }
    const end = Math.min(offset + limit, lines.length + 1)
    const out = []
    for (let i = offset; i < end; i += 1) {
      const n = i
      out.push(n + '#' + lineHash(lines[i - 1], n) + '| ' + lines[i - 1])
    }
    return out.join('\n')
  },
})

// ---------------------------------------------------------------------------
// hashline_edit
// ---------------------------------------------------------------------------

const EDIT_KINDS = new Set(['replace', 'append', 'prepend'])

/** Structural validation of one op (bounds/hashes are checked against the file). */
function validateOpShape(op, index) {
  const label = 'hashline_edit: op[' + index + ']'
  if (op === null || typeof op !== 'object') throw new Error(label + ' must be an object')
  if (typeof op.kind !== 'string' || !EDIT_KINDS.has(op.kind)) {
    throw new Error(label + ' kind must be one of replace, append, prepend')
  }
  if (!Number.isInteger(op.line) || op.line < 1) {
    throw new Error(label + ' line must be a positive integer')
  }
  if (op.hash !== undefined && op.hash !== null && typeof op.hash !== 'string') {
    throw new Error(label + ' hash must be a string')
  }
  if (typeof op.text !== 'string') {
    throw new Error(label + ' text must be a string')
  }
}

/** Number of prior inserts anchored at a smaller line number. */
function priorInsertsBefore(insertCountAt, line) {
  let total = 0
  for (const [anchor, count] of insertCountAt) {
    if (anchor < line) total += count
  }
  return total
}

/**
 * Current array index of an ORIGINAL line after the inserts applied so far:
 * original position + prior inserts before it + prior prepends at the line
 * itself (appends after the line do not move the line).
 */
function currentIndex(insertCountAt, prependCountAt, line) {
  return (line - 1) + priorInsertsBefore(insertCountAt, line)
    + (prependCountAt.get(line) ?? 0)
}

const hashlineEditTool = defineTool({
  name: 'hashline_edit',
  description:
    'Apply hash-anchored edits to a file. Each op references a line by the 1-based line number '
    + 'from read_hashline and carries the line\'s expected ID tag. Before any write the tool '
    + 're-reads the file and recomputes every referenced hash; on ANY mismatch it returns an error '
    + 'listing the failed line/hash pairs and does NOT modify the file — re-read with read_hashline '
    + 'and retry with fresh anchors. Ops apply in the order given: replace swaps the line text, '
    + 'append inserts after the referenced line, prepend inserts before it. All line numbers refer '
    + 'to the file as last read, not to intermediate states. The write is atomic (temp file + '
    + 'rename).',
  parameters: {
    path: {
      type: 'string',
      required: true,
      description: 'Path to the file to edit; relative paths resolve against the session workspace.',
    },
    ops: {
      type: 'array',
      required: true,
      description: 'Ordered edit operations, each {kind, line, hash?, text}. kind: replace | append | prepend.',
      items: {
        type: 'object',
        additionalProperties: false,
        properties: {
          kind: {
            type: 'string',
            enum: ['replace', 'append', 'prepend'],
            required: true,
            description: 'replace swaps the line text; append inserts after the line; prepend inserts before the line.',
          },
          line: {
            type: 'integer',
            required: true,
            description: '1-based line number from read_hashline.',
          },
          hash: {
            type: 'string',
            description: 'Expected ID tag for the line (from read_hashline); verified against the current file. Required for replace, optional for append/prepend.',
          },
          text: {
            type: 'string',
            required: true,
            description: 'New line text (replace) or text to insert (append/prepend).',
          },
        },
      },
    },
  },
  output: {
    schema: {
      type: 'object',
      additionalProperties: false,
      properties: {
        ok: { type: 'boolean', required: true },
        changedLines: { type: 'integer', required: true },
        path: { type: 'string', required: true },
      },
    },
    render: (_args, value) => {
      const text = value.ok
        ? 'hashline_edit: changed ' + value.changedLines + ' line(s) in ' + value.path
        : 'hashline_edit: failed for ' + value.path
      return [{ type: 'text', text }]
    },
  },
  isConcurrencySafe: () => false,
  timeoutMs: 30_000,
  async execute(args, exec) {
    const filePath = resolvePath(args.path, exec)
    const ops = args.ops
    if (!Array.isArray(ops) || ops.length === 0) {
      throw new Error('hashline_edit: ops must be a non-empty array of {kind, line, hash?, text}')
    }
    for (let i = 0; i < ops.length; i += 1) validateOpShape(ops[i], i)

    const content = await readFile(filePath, 'utf8')
    const { lines, eol, endsWithNewline } = splitLines(content)

    // Verify every referenced line/hash against the CURRENT file content.
    const failures = []
    for (const op of ops) {
      const line = op.line
      if (line > lines.length) {
        failures.push('line ' + line + ' (out of bounds; file has ' + lines.length + ' lines)')
        continue
      }
      if (op.hash !== undefined && op.hash !== null && op.hash !== '') {
        const actual = lineHash(lines[line - 1], line)
        if (actual !== op.hash) {
          failures.push(line + '#' + op.hash + ' (current tag ' + actual + ')')
        }
      }
    }
    if (failures.length > 0) {
      throw new Error('hashline_edit: stale reference(s) — file changed since read: '
        + failures.join('; ') + '. File NOT modified; re-run read_hashline and use the updated anchors.')
    }

    // Apply ops in order; line numbers keep referring to the original file.
    const work = lines.slice()
    const insertCountAt = new Map()
    const prependCountAt = new Map()
    const appendCountAt = new Map()
    let changed = 0
    for (const op of ops) {
      if (op.kind === 'replace') {
        work[currentIndex(insertCountAt, prependCountAt, op.line)] = op.text
      } else if (op.kind === 'append') {
        const at = currentIndex(insertCountAt, prependCountAt, op.line) + 1
          + (appendCountAt.get(op.line) ?? 0)
        work.splice(at, 0, op.text)
        appendCountAt.set(op.line, (appendCountAt.get(op.line) ?? 0) + 1)
        insertCountAt.set(op.line, (insertCountAt.get(op.line) ?? 0) + 1)
      } else {
        const at = currentIndex(insertCountAt, prependCountAt, op.line)
        work.splice(at, 0, op.text)
        prependCountAt.set(op.line, (prependCountAt.get(op.line) ?? 0) + 1)
        insertCountAt.set(op.line, (insertCountAt.get(op.line) ?? 0) + 1)
      }
      changed += 1
    }

    // Atomic write: temp file in the same directory, then rename over the target.
    const out = joinLines(work, eol, endsWithNewline)
    const tmp = filePath + '.hashline-tmp.' + process.pid + '.' + Date.now()
    await writeFile(tmp, out, 'utf8')
    try {
      await rename(tmp, filePath)
    } catch (error) {
      await rm(tmp, { force: true }).catch(() => {})
      throw error
    }
    return { ok: true, changedLines: changed, path: filePath }
  },
})

// ---------------------------------------------------------------------------
// plugin entry
// ---------------------------------------------------------------------------

/**
 * Register the two hashline tools.
 * @param ctx - registrant context.
 */
export function apply(ctx) {
  ctx.tools.register(readHashlineTool)
  ctx.tools.register(hashlineEditTool)
}
