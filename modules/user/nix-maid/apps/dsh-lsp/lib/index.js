/**
 * dsh-lsp: symbol-aware code intelligence via the Language Server Protocol.
 *
 * Ported from omp's lsp tool (plan: docs/howto/agent-deferred.ru.md §1). One
 * `lsp` tool; a pool of LSP servers keyed by (adapter, project root); servers
 * are spawned on first use and shut down with the plugin. Ops: hover, definition,
 * references, rename (preview or apply), code_actions (list).
 *
 * v1 limitations: positions are UTF-16 code-unit based (like VS Code; fine for
 * ASCII, approximate for astral chars); no diagnostics op; rename applies edits
 * directly (same trust level as bash/edit).
 */

import { spawn } from 'node:child_process'
import { readFile, writeFile, rename as fsRename } from 'node:fs/promises'
import { extname, join, dirname } from 'node:path'
import { pathToFileURL, fileURLToPath } from 'node:url'
import { existsSync, readFileSync } from 'node:fs'
import { defineTool } from '@deepseek-ai/dsh-tools'

export const name = 'dsh-lsp'
export const inject = ['tools']

const CRLF = String.fromCharCode(13) + String.fromCharCode(10)

const ADAPTERS = {
  'rust-analyzer': { command: 'rust-analyzer', args: [], extensions: ['.rs'], languageId: 'rust' },
  clangd: { command: 'clangd', args: [], extensions: ['.c', '.cc', '.cpp', '.h', '.hpp'], languageId: 'cpp' },
  pyright: { command: 'pyright-langserver', args: ['--stdio'], extensions: ['.py'], languageId: 'python' },
  'typescript-language-server': {
    command: 'typescript-language-server',
    args: ['--stdio'],
    extensions: ['.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs'],
    languageId: 'typescript',
  },
}

function languageIdFor(file) {
  const ext = extname(file).toLowerCase()
  const order = ['rust-analyzer', 'clangd', 'pyright', 'typescript-language-server']
  for (const id of order) {
    if (ADAPTERS[id].extensions.indexOf(ext) !== -1) return ADAPTERS[id].languageId
  }
  return null
}

function adapterFor(file, override) {
  if (override && ADAPTERS[override]) return override
  const ext = extname(file).toLowerCase()
  const order = ['rust-analyzer', 'clangd', 'pyright', 'typescript-language-server']
  for (const id of order) {
    if (ADAPTERS[id].extensions.indexOf(ext) !== -1) return id
  }
  return null
}

/** LSP client over stdio with Content-Length framing (same shape as DapClient). */
class LspClient {
  constructor(command, args, cwd) {
    this.proc = spawn(command, args, { stdio: ['pipe', 'pipe', 'pipe'], cwd: cwd })
    this.buf = Buffer.alloc(0)
    this.nextId = 1
    this.pending = new Map()
    this.onNotification = null
    const self = this
    this.proc.stdout.on('data', function (d) { self._onData(d) })
    this.proc.stderr.on('data', function (d) { self.lastError = String(d).slice(0, 400) })
  }

  _onData(d) {
    this.buf = Buffer.concat([this.buf, d])
    for (;;) {
      const marker = CRLF + CRLF
      const headerEnd = this.buf.indexOf(marker)
      if (headerEnd < 0) break
      const header = this.buf.slice(0, headerEnd).toString('utf8')
      let len = 0
      const lines = header.split(CRLF)
      for (const line of lines) {
        const colon = line.indexOf(':')
        if (colon > 0 && line.slice(0, colon).trim().toLowerCase() === 'content-length') {
          len = parseInt(line.slice(colon + 1).trim(), 10) || 0
        }
      }
      const start = headerEnd + marker.length
      if (this.buf.length < start + len) break
      const body = this.buf.slice(start, start + len).toString('utf8')
      this.buf = this.buf.slice(start + len)
      this._dispatch(body)
    }
  }

  _dispatch(body) {
    let msg
    try { msg = JSON.parse(body) } catch (e) { return }
    if (msg.id !== undefined && msg.id !== null && (msg.result !== undefined || msg.error !== undefined)) {
      const p = this.pending.get(msg.id)
      if (p) {
        this.pending.delete(msg.id)
        if (msg.error) p.reject(new Error('lsp ' + (msg.error.message || 'error')))
        else p.resolve(msg.result)
      }
    } else if (msg.method) {
      if (this.onNotification) this.onNotification(msg)
    }
  }

  request(method, params, timeoutMs) {
    const id = this.nextId
    this.nextId += 1
    const body = JSON.stringify({ jsonrpc: '2.0', id: id, method: method, params: params || {} })
    const payload = 'Content-Length: ' + Buffer.byteLength(body) + CRLF + CRLF + body
    const self = this
    return new Promise(function (resolve, reject) {
      const timer = setTimeout(function () {
        if (self.pending.has(id)) {
          self.pending.delete(id)
          reject(new Error('lsp request timed out: ' + method))
        }
      }, timeoutMs || 45000)
      self.pending.set(id, {
        resolve: function (v) { clearTimeout(timer); resolve(v) },
        reject: function (e) { clearTimeout(timer); reject(e) },
      })
      self.proc.stdin.write(payload, function (err) {
        if (err) {
          self.pending.delete(id)
          clearTimeout(timer)
          reject(err)
        }
      })
    })
  }

  notify(method, params) {
    const body = JSON.stringify({ jsonrpc: '2.0', method: method, params: params || {} })
    const payload = 'Content-Length: ' + Buffer.byteLength(body) + CRLF + CRLF + body
    try { this.proc.stdin.write(payload) } catch (e) { /* ignore */ }
  }

  close() {
    try {
      this.proc.stdin.end()
    } catch (e) { /* ignore */ }
    try { this.proc.kill('SIGTERM') } catch (e) { /* ignore */ }
  }
}

/** Pool: key = adapterId + ':' + root -> { client, root, opened:Set<uri> } */
const pool = new Map()

async function openClient(adapterId, root) {
  const key = adapterId + ':' + root
  let entry = pool.get(key)
  if (entry) return entry
  const adapter = ADAPTERS[adapterId]
  const client = new LspClient(adapter.command, adapter.args, root)
  try {
    const rootUri = pathToFileURL(root).href
    await client.request('initialize', {
      processId: null,
      clientInfo: { name: 'dsh' },
      rootUri: rootUri,
      workspaceFolders: [{ uri: rootUri, name: 'workspace' }],
      // Empty capabilities: strict servers (rust-analyzer) reject partial
      // capability objects with missing required fields; empty is accepted.
      capabilities: {},
    })
    client.notify('initialized', {})
  } catch (err) {
    client.close()
    throw err
  }
  entry = { client: client, root: root, opened: new Set() }
  pool.set(key, entry)
  return entry
}

function sessionRoot(exec) {
  const header = exec && exec.agent && exec.agent.session && exec.agent.session.header
  return (header && header.cwd) || process.cwd()
}

function toUri(path) {
  return pathToFileURL(path).href
}

function positionFor(file, line1, symbol) {
  let content = ''
  try {
    content = readFileSync(file, 'utf8')
  } catch (e) { /* keep empty */ }
  const lines = content.split('\n')
  const idx = Math.max(0, Number(line1) - 1)
  const text = lines[idx] !== undefined ? lines[idx] : ''
  const col = symbol ? text.indexOf(symbol) : 0
  return { line: idx, character: col < 0 ? 0 : col }
}

function locationLabel(loc) {
  if (Array.isArray(loc)) {
    return loc.map(function (l) { return locationLabel(l) })
  }
  if (loc && loc.uri) {
    const p = fileURLToPath(loc.uri)
    const r = loc.range || {}
    const start = r.start || {}
    return p + ':' + ((start.line || 0) + 1) + ':' + ((start.character || 0) + 1)
  }
  if (loc && loc.targetUri) return fileURLToPath(loc.targetUri) + ':' + (loc.targetSelectionRange ? 'sel' : '')
  return String(loc)
}

async function openDocument(entry, file) {
  const uri = toUri(file)
  if (entry.opened.has(uri)) return
  const text = await readFile(file, 'utf8')
  const lang = languageIdFor(file) || 'plaintext'
  entry.client.notify('textDocument/didOpen', {
    textDocument: { uri: uri, languageId: lang, version: 1, text: text },
  })
  entry.opened.add(uri)
}

function collectEdits(edit) {
  const out = []
  if (edit && edit.changes) {
    Object.keys(edit.changes).forEach(function (uri) {
      out.push({ uri: uri, edits: edit.changes[uri] })
    })
  }
  if (edit && Array.isArray(edit.documentChanges)) {
    edit.documentChanges.forEach(function (dc) {
      if (dc && dc.textDocument && dc.textDocument.uri && Array.isArray(dc.edits)) {
        out.push({ uri: dc.textDocument.uri, edits: dc.edits })
      }
    })
  }
  return out
}

async function applyWorkspaceEdit(edit) {
  const files = collectEdits(edit)
  const summary = []
  for (const f of files) {
    const path = fileURLToPath(f.uri)
    const text = await readFile(path, 'utf8')
    const lines = text.split('\n')
    const ordered = f.edits.slice().sort(function (a, b) {
      const sa = a.range.start.line * 100000 + a.range.start.character
      const sb = b.range.start.line * 100000 + b.range.start.character
      return sb - sa
    })
    for (const e of ordered) {
      const startLine = e.range.start.line
      const endLine = e.range.end.line
      const startCh = e.range.start.character
      const endCh = e.range.end.character
      const before = lines.slice(0, startLine)
      const midLines = lines.slice(startLine, endLine + 1)
      const head = midLines.length > 0 ? midLines[0].slice(0, startCh) : ''
      const tail = midLines.length > 0 ? midLines[midLines.length - 1].slice(endCh) : ''
      const replaced = head + e.newText + tail
      const after = lines.slice(endLine + 1)
      lines.splice(0, lines.length, ...before, replaced, ...after)
    }
    await writeFile(path, lines.join('\n'), 'utf8')
    summary.push({ file: path, edits: ordered.length })
  }
  return summary
}

async function withClient(params, exec, fn) {
  const file = params.file
  if (!file) throw new Error('lsp: file is required')
  const root = sessionRoot(exec)
  const resolved = String(file).startsWith('/') ? String(file) : join(root, String(file))
  if (!existsSync(resolved)) throw new Error('lsp: file does not exist: ' + resolved)
  const adapterId = adapterFor(resolved, params.adapter)
  if (!adapterId) throw new Error('lsp: no adapter for ' + resolved)
  const entry = await openClient(adapterId, root)
  await openDocument(entry, resolved)
  // Let slow analyzers (rust-analyzer) finish loading before answering.
  await new Promise(function (r) { setTimeout(r, 800) })
  const position = positionFor(resolved, params.line, params.symbol)
  return fn(entry.client, entry, resolved, position)
}

const OPS = {
  hover: function (params, exec) {
    return withClient(params, exec, async function (client, _entry, resolved, pos) {
      const res = await client.request('textDocument/hover', {
        textDocument: { uri: toUri(resolved) },
        position: pos,
      })
      if (!res) return { hover: null }
      const c = res.contents
      if (typeof c === 'string') return { hover: c }
      if (Array.isArray(c)) return { hover: c.map(function (x) { return typeof x === 'string' ? x : x.value }).join('\n') }
      if (c && typeof c.value === 'string') return { hover: c.value }
      return { hover: JSON.stringify(res) }
    })
  },
  definition: function (params, exec) {
    return withClient(params, exec, async function (client, _entry, resolved, pos) {
      const res = await client.request('textDocument/definition', {
        textDocument: { uri: toUri(resolved) },
        position: pos,
      })
      return { locations: locationLabel(res) }
    })
  },
  references: function (params, exec) {
    return withClient(params, exec, async function (client, _entry, resolved, pos) {
      const res = await client.request('textDocument/references', {
        textDocument: { uri: toUri(resolved) },
        position: pos,
        context: { includeDeclaration: true },
      })
      return { locations: locationLabel(res) }
    })
  },
  rename: function (params, exec) {
    return withClient(params, exec, async function (client, _entry, resolved, pos) {
      if (!params.new_name) throw new Error('lsp: rename needs new_name')
      const edit = await client.request('textDocument/rename', {
        textDocument: { uri: toUri(resolved) },
        position: pos,
        newName: String(params.new_name),
      })
      if (!edit) return { edits: [] }
      if (params.apply === false) {
        return { preview: collectEdits(edit).map(function (f) {
          return { file: fileURLToPath(f.uri), edits: f.edits.length }
        }) }
      }
      const summary = await applyWorkspaceEdit(edit)
      return { applied: summary }
    })
  },
  code_actions: function (params, exec) {
    return withClient(params, exec, async function (client, _entry, resolved, pos) {
      const res = await client.request('textDocument/codeAction', {
        textDocument: { uri: toUri(resolved) },
        range: { start: pos, end: pos },
        context: { diagnostics: [] },
      })
      const actions = Array.isArray(res) ? res : []
      return { actions: actions.map(function (a, i) {
        return { index: i, title: a.title || '', kind: (a.kind || '').split('.')[0] }
      }) }
    })
  },
}

function lspTool() {
  const opNames = Object.keys(OPS)
  return defineTool({
    name: 'lsp',
    description: 'Symbol-aware code intelligence via LSP. Prefer over text search for navigation, ' +
      'rename, references. Ops: ' + opNames.join(', ') + '. line is 1-based; symbol is a substring ' +
      'on that line used to locate the cursor (empty = start of line). rename applies edits unless ' +
      'apply:false (preview). Adapters auto-selected by extension: rust-analyzer (.rs), clangd ' +
      '(.c/.cpp/.h), pyright (.py), typescript-language-server (.ts/.js).',
    parameters: {
      op: { type: 'string', required: true, description: 'One of: ' + opNames.join(', ') },
      file: { type: 'string', required: true, description: 'File path (absolute or workspace-relative).' },
      line: { type: 'integer', description: '1-based line of the cursor (default 1).' },
      symbol: { type: 'string', description: 'Substring on that line to locate the cursor.' },
      new_name: { type: 'string', description: 'New name for rename.' },
      apply: { type: 'boolean', description: 'rename: apply edits (default true); false = preview.' },
      adapter: { type: 'string', description: 'Adapter override: rust-analyzer | clangd | pyright | typescript-language-server.' },
    },
    output: {
      schema: { type: 'object', additionalProperties: true },
      render: function (_args, value) {
        return [{ type: 'text', text: JSON.stringify(value, null, 2) }]
      },
    },
    isConcurrencySafe: function () { return false },
    timeoutMs: 60000,
    async execute(args, exec) {
      const op = OPS[args.op]
      if (!op) throw new Error('lsp: unknown op ' + args.op)
      return await op(args, exec)
    },
  })
}

export function apply(ctx) {
  ctx.tools.register(lspTool())
  ctx.effect(function () {
    return function () {
      pool.forEach(function (entry) {
        try { entry.client.close() } catch (e) { /* ignore */ }
      })
      pool.clear()
    }
  }, name + ': shutdown')
}
