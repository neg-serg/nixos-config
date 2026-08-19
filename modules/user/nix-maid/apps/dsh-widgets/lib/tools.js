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

// bash_live streams command output to the web GUI by appending purely
// informational `tool/bash-live-*` events to the durable session log (the
// full output always returns in the tool result). rc.6's Session.append()
// cannot set the envelope's `ignorable` marker, and the harness defers the
// out-of-repo plugin-event registration surface — so the events used to be
// written non-ignorable and any session that used bash_live was refused by
// the history reader (SessionFormatUnsupportedError). Fixed in two halves:
// the staged harness patch makes `append(type, data, { ignorable: true })`
// carry the marker on the envelope (packages/dsh/patch-widgets.py), and the
// append helper below passes it for these events. dsh-selfheal additionally
// auto-repairs logs written before the fix.

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
 * Build the `bash_live` tool: runs a shell command and streams its output to
 * the web GUI live. Unlike the stock `bash` (which awaits the whole process
 * and returns output only on settle), this tool launches the process through
 * `ctx.shell.start`, polls incremental `readOutput()` deltas, and appends them
 * to the session as `tool/bash-live-*` events (`session.append` — the same
 * durable-event seam the workflow tool uses for its run panel). The client
 * half of dsh-widgets folds those events into a live terminal chat node.
 *
 * The full streamed output is also returned in the tool result, so the model
 * sees everything regardless of the live-stream event cap.
 *
 * @param ctx - registrant context carrying `ctx.shell` (and optionally
 *   `sandboxPolicy` / `shellEnv` via ctx.get).
 */
export function createBashLiveTool(ctx) {
  const POLL_MS = 120
  const MAX_STREAM_EVENTS = 500
  const MAX_OUTPUT_CHARS = 262_144

  return defineTool({
    name: 'bash_live',
    description:
      'Run a shell command and stream its output to the web GUI live — the user watches the output appear '
      + 'in a terminal card while the command runs, not after it settles. Use for long-running commands '
      + '(builds, installs, tests, logs) when live progress is useful; for quick commands the plain `bash` '
      + 'tool is fine. The full output is still returned as the tool result.',
    parameters: {
      command: {
        type: 'string',
        required: true,
        description: 'The shell command to run.',
      },
      workdir: {
        type: 'string',
        description: 'Working directory; defaults to the session workspace root.',
      },
      timeoutMs: {
        type: 'integer',
        description: 'Kill the command after this many milliseconds.',
      },
    },
    output: {
      schema: {
        type: 'object',
        additionalProperties: false,
        properties: {
          status: { type: 'string', required: true, enum: ['completed', 'killed'] },
          detail: { type: 'string', required: true },
          output: { type: 'string', required: true },
          streamCapped: { type: 'boolean' },
        },
      },
      render: (_args, value) => [{
        type: 'text',
        text: `${value.output}${value.output.length > 0 && !value.output.endsWith('\n') ? '\n' : ''}[${value.detail}]${value.streamCapped === true ? '\n[live stream capped; this result holds the full output]' : ''}`,
      }],
    },
    isConcurrencySafe: () => true,
    async execute(args, exec) {
      const command = String(args.command ?? '').trim()
      if (command === '') throw new Error('bash_live: command must not be empty')

      // Mirror the stock bash tool's request construction: sandbox policy +
      // session workspace root as the default cwd + the model's env.
      const sandboxPolicy = ctx.get('sandboxPolicy')?.resolve({
        ...exec.agent ? { session: exec.agent.session } : {},
      })
      const session = exec.agent?.session
      const shellEnv = ctx.get('shellEnv')
      const workdir = typeof args.workdir === 'string' && args.workdir.trim() !== ''
        ? args.workdir.trim()
        : exec.agent?.session?.header?.cwd
      const request = {
        command,
        ...workdir !== undefined ? { workdir } : {},
        ...typeof args.timeoutMs === 'number' ? { timeoutMs: args.timeoutMs } : {},
        ...shellEnv !== undefined && typeof shellEnv.collect === 'function' ? { dshEnv: shellEnv.collect(exec) } : {},
        ...sandboxPolicy !== undefined ? { sandboxPolicy } : {},
      }
      const spec = ctx.shell.resolve({ ...request, signal: exec.signal })

      const runId = 'bl-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 6)
      const append = (type, data) => {
        if (session !== undefined && session !== null && typeof session.append === 'function') {
          try {
            // The staged dsh-session patch (packages/dsh/patch-widgets.py)
            // carries this option onto the event envelope as `ignorable: true`,
            // which is what keeps the history reader from refusing the log.
            session.append(type, data, { ignorable: true })
          } catch {
            /* a failed event must never break the tool */
          }
        }
      }

      append('tool/bash-live-start', { id: runId, command })

      let output = ''
      let emitted = 0
      let truncated = false
      const proc = ctx.shell.start(spec)
      try {
        while (true) {
          const read = proc.readOutput()
          if (read !== null && typeof read === 'object' && typeof read.delta === 'string' && read.delta !== '') {
            if (output.length < MAX_OUTPUT_CHARS) {
              const room = MAX_OUTPUT_CHARS - output.length
              output += read.delta.length > room ? read.delta.slice(0, room) : read.delta
              if (output.length >= MAX_OUTPUT_CHARS) truncated = true
            }
            if (emitted < MAX_STREAM_EVENTS) {
              // Split oversized deltas so one event never bloats the session log.
              let rest = read.delta
              while (rest !== '' && emitted < MAX_STREAM_EVENTS) {
                const chunk = rest.slice(0, 16_000)
                rest = rest.slice(16_000)
                emitted += 1
                append('tool/bash-live-output', { id: runId, chunk })
              }
            }
          }
          const settled = await Promise.race([
            proc.done.then(() => true).catch(() => true),
            new Promise((resolve) => setTimeout(() => resolve(false), POLL_MS)),
          ])
          if (settled) break
        }
        const tail = proc.readOutput()
        if (tail !== null && typeof tail === 'object' && typeof tail.delta === 'string' && tail.delta !== '') {
          const room = MAX_OUTPUT_CHARS - output.length
          if (room > 0) output += tail.delta.slice(0, Math.max(0, room))
        }
      } catch (error) {
        append('tool/bash-live-end', { id: runId, status: 'killed', detail: String(error?.message ?? error) })
        throw error
      }

      const status = proc.status === 'killed' ? 'killed' : 'completed'
      const detail = status === 'killed'
        ? `killed by signal: ${proc.signal ?? '?'}`
        : `exit code: ${proc.exitCode ?? 0}`
      const streamCapped = emitted >= MAX_STREAM_EVENTS
      append('tool/bash-live-end', { id: runId, status, detail, ...(streamCapped ? { streamCapped: true } : {}) })
      return { status, detail, output, ...(streamCapped ? { streamCapped: true } : {}) }
    },
    presentCall: () => ({ card: 'generic', title: 'bash · live', kind: 'other' }),
    presentResult: (_args, result) => {
      if (result.isError) return undefined
      return { card: 'generic', title: 'bash · live' }
    },
  })
}

/**
 * Build the widget tools.
 * @param ctx - registrant context (needed by `bash_live` for ctx.shell).
 * @param config - { maxInputBytes, maxMetaBytes, enableBashLive }.
 * @returns the tool definitions to register on ctx.tools (`bash_live` only
 * when `enableBashLive` is set).
 */
export function createWidgetTools(ctx, config) {
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
          expand: { type: 'integer' },
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

  const tools = [jsonTool]
  if (config.enableBashLive) {
    tools.push(createBashLiveTool(ctx))
  }
  return tools
}
