/**
 * dsh-read-tags — tag every line the built-in `read` tool returns with a
 * LINE#ID content-hash anchor, so anchors from plain `read` can be fed
 * straight into hashline_edit (phase 2 of the hashline design).
 *
 * Implementation: a `tools/post-execute` listener replaces the rendered
 * content of top-level `read` calls with the same `N#ID| text` format the
 * dsh-hashline `read_hashline` tool produces (identical hash function, same
 * normalization), while leaving the structured `value`/`meta` untouched so
 * the web GUI keeps its structured view.
 *
 * Composition: the listener is NOT prepended — dsh-spill-policy registers
 * with { prepend: true } and bounds whatever content this listener produces,
 * so oversized tagged output still gets spilled instead of flooding context.
 *
 * Hash normalization matches dsh-hashline exactly: CR stripped, trailing
 * whitespace trimmed; a blank line hashes its 1-based line number.
 * @module dsh-read-tags
 */

import { createHash } from 'node:crypto'

/** Cordis plugin name — must match the patch row / package name. */
export const name = 'dsh-read-tags'

/** The tool registry must be loaded for the post-execute waterfall to exist. */
export const inject = ['tools']

// ---------------------------------------------------------------------------
// hashing — MUST stay byte-identical to dsh-hashline (lineHash)
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
 * Two-char LINE#ID tag body for one line (identical to dsh-hashline).
 * Normalization: CR stripped, trailing whitespace trimmed. A blank line hashes
 * its 1-based line number instead of the empty string.
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
// read content projection
// ---------------------------------------------------------------------------

/**
 * Re-render a successful `read` result in the same shape the built-in tool
 * uses, but with `N#ID| text` lines so every anchor is hashline_edit-ready.
 * @param value - the structured `read` value ({path, offset, lines, totalLines}).
 * @returns the replacement content text.
 */
function buildTaggedRead(value) {
  const endLine = value.lines.at(-1)?.number ?? Math.max(0, value.offset - 1)
  let footer
  if (endLine < value.totalLines) {
    footer = `(Showing lines ${value.offset}-${endLine} of ${value.totalLines}. Use offset=${endLine + 1} to continue.)`
  } else {
    footer = `(End of file - total ${value.totalLines} lines)`
  }
  const body = value.lines.length > 0
    ? `${value.lines.map((line) => `${line.number}#${lineHash(line.text, line.number)}| ${line.text}`).join('\n')}\n\n${footer}`
    : footer
  return `<path>${value.path}</path>\n<type>file</type>\n<content>\n${body}\n</content>`
}

// ---------------------------------------------------------------------------
// plugin entry
// ---------------------------------------------------------------------------

/**
 * Register the post-execute listener that tags `read` output.
 * @param ctx - registrant context.
 */
export function apply(ctx) {
  ctx.on('tools/post-execute', async (exec, result, next) => {
    const decision = await next()
    if (decision.kind !== 'accept') return decision
    if (exec.name !== 'read') return decision
    if (exec.parent !== void 0) return decision // nested run_code reads keep plain output
    const value = result && result.value
    if (!value || !Array.isArray(value.lines)) return decision
    return {
      kind: 'accept',
      content: [{ type: 'text', text: buildTaggedRead(value) }]
    }
  })
}
