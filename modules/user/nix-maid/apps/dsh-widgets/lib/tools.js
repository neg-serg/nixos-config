/**
 * dsh-widgets — model-facing tool.
 *
 * One general-purpose `json` tool: take a raw JSON string, validate it, and
 * project a `{ kind: 'json-tree', value, … }` presentationMeta descriptor the
 * web client renders as a collapsible syntax-highlighted tree. A parse error
 * is a *result* (rendered as an error card), not a throw, so the model sees a
 * useful message; only an oversized input throws (isError).
 *
 * Replay-stable by construction: the descriptor (parsed value + counts) is
 * persisted with the session log, so replay re-renders the same tree from
 * logged data with no re-parse and no live tool call — the same guarantee
 * dsh-osm documents for its map descriptor.
 *
 * @module dsh-widgets/tools
 */

import { defineTool } from '@deepseek-ai/dsh-tools'

const TOOL_NAME = 'json'

const DESCRIPTION =
  'Show the user a JSON value as a collapsible, syntax-highlighted tree card in the web GUI. '
  + 'Pass the raw JSON text in `json` (it is parsed and validated); `title` labels the card, and '
  + '`expand` sets how many levels are expanded initially. Invalid JSON is reported as an error '
  + 'card, not a thrown failure. Use this instead of pasting a big raw JSON dump into prose '
  + 'whenever a structured value would read better as a tree.'

/**
 * Iteratively count nodes and measure max nesting depth without recursion, so
 * very deep or wide values cannot overflow the call stack.
 * @param value - any parsed JSON value.
 * @returns { nodes, depth }.
 */
function measure(value) {
  let nodes = 0
  let depth = 0
  const stack = [{ v: value, d: 1 }]
  while (stack.length > 0) {
    const { v, d } = stack.pop()
    nodes += 1
    if (d > depth) depth = d
    if (Array.isArray(v)) {
      for (let i = v.length - 1; i >= 0; i -= 1) stack.push({ v: v[i], d: d + 1 })
    } else if (v !== null && typeof v === 'object') {
      const keys = Object.keys(v)
      for (let i = keys.length - 1; i >= 0; i -= 1) stack.push({ v: v[keys[i]], d: d + 1 })
    }
  }
  return { nodes, depth }
}

/**
 * Truncate one parsed value to a bounded preview (first N object entries /
 * array items), returning the preview and the number of omitted nodes.
 * @param value - the parsed value.
 * @param max - max entries/items to keep per level.
 * @returns { value, omitted }.
 */
function previewValue(value, max) {
  let omitted = 0
  const copy = (v, depth) => {
    if (depth > 16) return v // stop nesting the preview deep
    if (Array.isArray(v)) {
      const out = []
      for (let i = 0; i < v.length; i += 1) {
        if (out.length >= max) { omitted += v.length - i; break }
        out.push(copy(v[i], depth + 1))
      }
      return out
    }
    if (v !== null && typeof v === 'object') {
      const out = {}
      const keys = Object.keys(v)
      for (let i = 0; i < keys.length; i += 1) {
        if (Object.keys(out).length >= max) { omitted += keys.length - i; break }
        out[keys[i]] = copy(v[keys[i]], depth + 1)
      }
      return out
    }
    return v
  }
  return { value: copy(value, 0), omitted }
}

/**
 * Shrink a meta descriptor until it fits maxBytes (progressive lossy trim).
 * @param meta - the full descriptor.
 * @param maxBytes - the persisted-meta ceiling.
 * @returns a descriptor that serializes under maxBytes.
 */
function capMeta(meta, maxBytes) {
  if (JSON.stringify(meta).length <= maxBytes) return meta
  const preview = previewValue(meta.value, 200)
  const trimmed = {
    ...meta,
    value: preview.value,
    truncated: true,
    truncatedNodes: preview.omitted,
  }
  if (JSON.stringify(trimmed).length <= maxBytes) return trimmed
  // Last resort: counts only, no value — the client renders a "drill in" banner.
  const { value: _drop, ...rest } = trimmed
  return rest
}

/**
 * Narrow an untrusted persisted `tool/result` meta value to the JSON-tree
 * descriptor, or undefined when it does not match the wire contract. Mirrors
 * dsh-osm's osmMetaFrom.
 * @param meta - the raw meta value.
 */
export function jsonMetaFrom(meta) {
  if (typeof meta !== 'object' || meta === null) return undefined
  const record = meta
  if (record.kind !== 'json-tree') return undefined
  if (typeof record.title !== 'string') return undefined
  const out = { kind: 'json-tree', title: record.title }
  if (Object.prototype.hasOwnProperty.call(record, 'value')) out.value = record.value
  for (const key of ['sizeBytes', 'nodes', 'depth', 'truncatedNodes']) {
    if (typeof record[key] === 'number' && Number.isFinite(record[key])) out[key] = record[key]
  }
  if (record.truncated === true) out.truncated = true
  if (typeof record.path === 'string') out.path = record.path
  if (typeof record.error === 'object' && record.error !== null && typeof record.error.message === 'string') {
    out.error = { message: record.error.message }
    if (typeof record.error.line === 'number') out.error.line = record.error.line
    if (typeof record.error.column === 'number') out.error.column = record.error.column
    if (typeof record.error.snippet === 'string') out.error.snippet = record.error.snippet
  }
  if (out.value === undefined && out.error === undefined) return undefined
  return out
}

function byteLength(text) {
  if (typeof Buffer !== 'undefined') return Buffer.byteLength(text, 'utf8')
  return new TextEncoder().encode(text).length
}

/** Extract line/column/offset + a short snippet from a JSON.parse SyntaxError. */
function parseErrorInfo(error) {
  const message = String(error?.message ?? 'invalid JSON')
  let line
  let column
  let offset
  if (typeof error?.message === 'string') {
    const pos = /\bposition (\d+)/u.exec(error.message)
    if (pos !== null) offset = Number(pos[1])
    const lc = /\bline (\d+) column (\d+)/u.exec(error.message)
    if (lc !== null) {
      line = Number(lc[1])
      column = Number(lc[2])
    }
  }
  return { message, line, column, offset }
}

/**
 * Build the `json` tool definition.
 * @param config - { maxInputBytes, maxMetaBytes }.
 * @returns the tool definition to register on ctx.tools.
 */
export function createWidgetTools(config) {
  const { maxInputBytes, maxMetaBytes } = config

  const jsonTool = defineTool({
    name: TOOL_NAME,
    description: DESCRIPTION,
    parameters: {
      json: {
        type: 'string',
        required: true,
        description:
          'The raw JSON text to parse and display as a tree. Any JSON value is accepted — object, '
          + 'array, or scalar (string/number/boolean/null).',
      },
      title: {
        type: 'string',
        description: 'Concise card title. Defaults to "JSON".',
      },
      expand: {
        type: 'integer',
        description: 'How many nesting levels are expanded initially (default 3; 0 = collapsed to root).',
      },
    },
    output: {
      schema: {
        type: 'object',
        additionalProperties: false,
        properties: {
          title: { type: 'string', required: true },
          sizeBytes: { type: 'integer', required: true },
          nodes: { type: 'integer', required: true },
          depth: { type: 'integer', required: true },
          path: { type: 'string', required: true },
          error: {
            type: 'object',
            additionalProperties: false,
            properties: {
              message: { type: 'string', required: true },
              line: { type: 'integer' },
              column: { type: 'integer' },
              offset: { type: 'integer' },
            },
          },
          value: { type: 'json', required: true },
        },
      },
      render: (_args, value) => {
        if (value.error !== undefined) {
          const at = value.error.line !== undefined
            ? ` (line ${value.error.line}, column ${value.error.column})`
            : ''
          return [{ type: 'text', text: `JSON parse error${at}: ${value.error.message}` }]
        }
        return [{
          type: 'text',
          text: `Rendered "${value.title}" as a JSON tree — ${value.nodes} node(s), depth ${value.depth}, ${value.sizeBytes} bytes.`,
        }]
      },
      presentationMeta: (_args, value) => {
        const base = {
          kind: 'json-tree',
          title: value.title,
          sizeBytes: value.sizeBytes,
          nodes: value.nodes,
          depth: value.depth,
          path: value.path,
        }
        if (value.error !== undefined) {
          return { ...base, error: value.error }
        }
        return capMeta({ ...base, value: value.value }, maxMetaBytes)
      },
    },
    isConcurrencySafe: () => true,
    async execute(args) {
      const text = typeof args.json === 'string' ? args.json : String(args.json ?? '')
      const sizeBytes = byteLength(text)
      if (sizeBytes > maxInputBytes) {
        throw new Error(
          `json: input is ${sizeBytes} bytes — cap is ${maxInputBytes} (${(maxInputBytes / 1e6).toFixed(1)} MB). ` +
          'Pass a smaller slice or pre-parse the interesting subtree.',
        )
      }
      const title = (typeof args.title === 'string' && args.title.trim() !== '') ? args.title.trim() : 'JSON'
      const expand = Math.max(0, Math.min(16, args.expand ?? 3))

      let parsed
      try {
        parsed = JSON.parse(text)
      } catch (error) {
        // JSON.parse throws SyntaxError on malformed text and RangeError on
        // extreme nesting. Both are a *result* (error card), not a throw.
        const info = parseErrorInfo(error)
        return {
          title,
          sizeBytes,
          nodes: 0,
          depth: 0,
          path: '$',
          error: info,
          value: null,
        }
      }

      const { nodes, depth } = measure(parsed)
      return { title, sizeBytes, nodes, depth, path: '$', value: parsed, expand }
    },
    presentCall: () => ({ card: 'generic', title: 'JSON', kind: 'other' }),
    presentResult(_args, result) {
      if (result.isError) return undefined
      const meta = jsonMetaFrom(result.meta)
      if (meta === undefined) return undefined
      return { card: 'generic', title: meta.error !== undefined ? 'JSON · parse error' : `JSON · ${meta.title}` }
    },
  })

  return [jsonTool]
}
