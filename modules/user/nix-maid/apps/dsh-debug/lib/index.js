/**
 * dsh-debug: DAP (Debug Adapter Protocol) debugging for DSH.
 *
 * Ported from omp's debug tool (design notes: omp src/tools/debug.ts +
 * src/dap/defaults.json). One `debug` tool, one active session: spawn a DAP
 * adapter over stdio (gdb -i dap / lldb-dap / dlv dap / python -m debugpy.adapter),
 * speak JSON-RPC with Content-Length framing, and expose launch/attach/
 * breakpoints/stepping/inspection/evaluate/terminate actions to the model.
 *
 * v1: read-only inspection plus exec actions on the same trust level as the
 * bash tool (no separate approval gate yet). Adapters auto-selected by file
 * extension; explicit `adapter` param overrides.
 */

import { spawn } from 'node:child_process'
import { connect as netConnect } from 'node:net'
import { extname, join, dirname, basename } from 'node:path'
import { existsSync } from 'node:fs'
import { defineTool } from '@deepseek-ai/dsh-tools'

export const name = 'dsh-debug'

export const inject = ['tools']

const CRLF = String.fromCharCode(13) + String.fromCharCode(10)

/** Built-in DAP adapter table (mirror of omp dap/defaults.json, host-relevant subset). */
const ADAPTERS = {
  gdb: {
    command: 'gdb',
    args: ['-i', 'dap'],
    extensions: ['.c', '.cc', '.cpp', '.cxx', '.rs', '.h', '.hh', '.hpp'],
    launch: { request: 'launch', stopOnEntry: true },
  },
  'lldb-dap': {
    command: 'lldb-dap',
    args: [],
    extensions: [],
    launch: { request: 'launch', stopOnEntry: true },
  },
  dlv: {
    command: 'dlv',
    args: ['dap'],
    extensions: ['.go'],
    launch: { request: 'launch' },
  },
  debugpy: {
    command: 'python3',
    args: ['-m', 'debugpy.adapter'],
    extensions: ['.py'],
    launch: { request: 'launch', type: 'python' },
  },
  'js-debug-adapter': {
    command: 'js-debug-adapter',
    // nixpkgs vscode-js-debug is a socket-only DAP server (usage:
    // dapDebugServer.js [port=8123]); our DapClient connects in socket mode.
    args: ['8123', '127.0.0.1'], // listen on IPv4 (default is ::1 only)
    socketPort: 8123,
    extensions: ['.js', '.jsx', '.mjs', '.cjs', '.ts', '.tsx'],
    launch: { request: 'launch', type: 'pwa-node', stopOnEntry: true },
  },
}

/**
 * Resolve an adapter command to an absolute path. Checks PATH, then common
 * user-level locations (js-debug-adapter is not on npm; comes from nixpkgs
 * vscode-js-debug or a VS Code install). Falls back to the bare name, so
 * spawn surfaces ENOENT with the adapter id in the error path.
 */
function resolveCommand(cmd) {
  // nixpkgs vscode-js-debug exposes the binary as 'js-debug' (not
  // 'js-debug-adapter' like VS Code's distribution)
  const names = cmd === 'js-debug-adapter' ? ['js-debug', 'js-debug-adapter'] : [cmd]
  const roots = [
    (process.env.HOME || '') + '/.npm-global/bin',
    (process.env.HOME || '') + '/.local/bin',
    '/usr/local/bin',
    '/run/current-system/sw/bin',
  ]
  for (const name of names) {
    for (const root of roots) {
      const p = root + '/' + name
      try {
        if (existsSync(p)) return p
      } catch (ex) { /* keep probing */ }
    }
  }
  return cmd
}

const READONLY_ACTIONS = new Set([
  'sessions', 'output', 'threads', 'stack_trace', 'scopes', 'variables',
  'loaded_sources', 'modules',
])

/** Minimal DAP client (stdio or socket transport) with Content-Length framing. */
class DapClient {
  constructor(command, args, socketPort) {
    this.socket = null
    this.ready = null
    this.lastError = ''
    const self = this
    if (socketPort) {
      // Socket mode: spawn the adapter (it listens), then connect with retry.
      this.proc = spawn(command, args, { stdio: ['ignore', 'ignore', 'pipe'] })
      this.ready = this._connectWithRetry(socketPort, 15, 200)
    } else {
      this.proc = spawn(command, args, { stdio: ['pipe', 'pipe', 'pipe'] })
      this.proc.stdout.on('data', function (d) { self._onData(d) })
    }
    this.buf = Buffer.alloc(0)
    this.nextSeq = 1
    this.pending = new Map()
    this.onEvent = null
    if (this.proc) {
      this.proc.stderr.on('data', function (d) {
        self.lastError = String(d).slice(0, 400)
      })
      this.proc.on('exit', function () {
        const err = new Error('debug adapter exited: ' + self.lastError)
        self.pending.forEach(function (p) { p.reject(err) })
        self.pending.clear()
      })
    }
  }

  _connectWithRetry(port, attempts, delay) {
    const self = this
    return new Promise(function (resolve, reject) {
      const tryOnce = function (n) {
        const s = netConnect(port, '127.0.0.1')
        const onErr = function (err) {
          s.destroy()
          if (n <= 0) reject(new Error('js-debug adapter connect failed: ' + String(err.message || err)))
          else setTimeout(function () { tryOnce(n - 1) }, delay)
        }
        s.once('error', onErr)
        s.once('connect', function () {
          s.removeListener('error', onErr)
          s.on('data', function (d) { self._onData(d) })
          self.socket = s
          resolve(s)
        })
      }
      tryOnce(attempts)
    })
  }

  write(payload) {
    if (this.socket) {
      this.socket.write(payload)
    } else {
      this.proc.stdin.write(payload)
    }
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
    if (msg.type === 'response') {
      const p = this.pending.get(msg.request_seq)
      if (p) {
        this.pending.delete(msg.request_seq)
        if (msg.success) p.resolve(msg)
        else p.reject(new Error('dap ' + msg.command + ': ' + (msg.message || 'failed')))
      }
    } else if (msg.type === 'event') {
      if (this.onEvent) this.onEvent(msg)
    }
  }

  async request(command, args) {
    if (this.ready) await this.ready
    const seq = this.nextSeq
    this.nextSeq += 1
    const body = JSON.stringify({ seq: seq, type: 'request', command: command, arguments: args || {} })
    const payload = 'Content-Length: ' + Buffer.byteLength(body) + CRLF + CRLF + body
    const self = this
    return new Promise(function (resolve, reject) {
      const timer = setTimeout(function () {
        if (self.pending.has(seq)) {
          self.pending.delete(seq)
          reject(new Error('dap request timed out: ' + command))
        }
      }, 30000)
      self.pending.set(seq, {
        resolve: function (v) { clearTimeout(timer); resolve(v) },
        reject: function (e) { clearTimeout(timer); reject(e) },
      })
      try {
        self.write(payload)
      } catch (e) {
        self.pending.delete(seq)
        clearTimeout(timer)
        reject(e)
      }
    })
  }

  close() {
    try { if (this.socket) this.socket.destroy(); else this.proc.stdin.end() } catch (e) { /* ignore */ }
    try { this.proc.kill('SIGTERM') } catch (e) { /* ignore */ }
  }
}

/** One active debug session. */
let active = null

function sessionCwd(exec) {
  const header = exec && exec.agent && exec.agent.session && exec.agent.session.header
  return (header && header.cwd) || process.cwd()
}

function selectAdapter(program, override) {
  if (override && ADAPTERS[override]) return override
  const ext = extname(String(program)).toLowerCase()
  const order = ['debugpy', 'dlv', 'gdb', 'lldb-dap']
  for (const id of order) {
    if (ADAPTERS[id].extensions.indexOf(ext) !== -1) return id
  }
  return 'gdb'
}

async function openSession(params, exec) {
  if (active) throw new Error('debug: a session is already active; terminate it first (action: terminate)')
  const program = params.program
  if (!program) throw new Error('debug: program is required for launch')
  const cwd = sessionCwd(exec)
  const resolved = String(program).startsWith('/') ? String(program) : join(cwd, String(program))
  if (!existsSync(resolved)) throw new Error('debug: program does not exist: ' + resolved)
  const adapterId = selectAdapter(resolved, params.adapter)
  const adapter = ADAPTERS[adapterId]
  const client = new DapClient(resolveCommand(adapter.command), adapter.args, adapter.socketPort)
  try {
    await initializeClient(client, adapterId)
    // Pre-set breakpoints BEFORE launch (required by js-debug for binding).
    const preBps = Array.isArray(params.breakpoints) ? params.breakpoints : []
    for (const bp of preBps) {
      if (!bp.file || !bp.line) continue
      const bpArgs = { source: { path: String(bp.file) }, breakpoints: [{ line: Number(bp.line) }] }
      if (bp.condition) bpArgs.breakpoints[0].condition = String(bp.condition)
      await client.request('setBreakpoints', bpArgs)
    }
    const launchArgs = {}
    const base = adapter.launch || { request: 'launch' }
    Object.keys(base).forEach(function (k) { launchArgs[k] = base[k] })
    launchArgs.program = resolved
    if (params.args) launchArgs.args = params.args
    if (params.cwd) launchArgs.cwd = String(params.cwd)
    launchArgs.cwd = launchArgs.cwd || cwd
    if (params.condition) launchArgs.condition = params.condition
    // Some adapters (gdb) defer the launch response until configurationDone:
    // send launch first, then configurationDone, then await the launch response.
    const launchResponse = client.request('launch', launchArgs)
    await client.request('configurationDone', {})
    await launchResponse
    await waitForStopped(client, 3000) // stopOnEntry: let the stopped event land (js-debug)
  } catch (err) {
    client.close()
    throw err
  }
  active = { client: client, adapterId: adapterId, program: resolved, threadId: undefined }
  return active
}

async function openAttach(params, exec) {
  if (active) throw new Error('debug: a session is already active; terminate it first (action: terminate)')
  const pid = params.pid
  const host = params.host || '127.0.0.1'
  const port = params.port
  if (pid === undefined && port === undefined) {
    throw new Error('debug: attach needs pid (local) or port (remote, optional host)')
  }
  // For remote (port) attach default to debugpy; for pid attach default to gdb.
  const adapterId = port !== undefined ? 'debugpy' : (params.adapter || 'gdb')
  const adapter = ADAPTERS[adapterId]
  if (!adapter) throw new Error('debug: unknown adapter ' + adapterId)
  const client = new DapClient(resolveCommand(adapter.command), adapter.args, adapter.socketPort)
  try {
    await initializeClient(client, adapterId)
    const attachArgs = { request: 'attach' }
    if (pid !== undefined) attachArgs.pid = Number(pid)
    if (port !== undefined) {
      attachArgs.connect = { host: String(host), port: Number(port) }
    }
    const attachResponse = client.request('attach', attachArgs)
    await client.request('configurationDone', {})
    await attachResponse
    await waitForStopped(client, 2000) // gdb reports threads after the stopped event
  } catch (err) {
    client.close()
    throw err
  }
  active = { client: client, adapterId: adapterId, program: 'attach:' + (pid !== undefined ? 'pid ' + pid : host + ':' + port), threadId: undefined }
  return active
}

async function initializeClient(client, adapterId) {
  await client.request('initialize', {
    adapterID: adapterId,
    clientID: 'dsh',
    clientName: 'dsh-debug',
    supportsVariableType: true,
    supportsEvaluateForHovers: true,
    supportsSetVariable: false,
    supportsConfigurationDoneRequest: true,
  })
}

/** Wait (bounded) for a stopped event so the next inspection is valid. */
function waitForStopped(client, ms) {
  return new Promise(function (resolve) {
    let done = false
    const timer = setTimeout(function () { cleanup(); resolve(false) }, ms)
    function onEvent(ev) {
      if (ev.event === 'stopped') { cleanup(); resolve(true) }
    }
    function cleanup() {
      clearTimeout(timer)
      client.onEvent = null
    }
    client.onEvent = onEvent
  })
}

async function threadIdOf(session) {
  if (session.threadId !== undefined) return session.threadId
  const resp = await session.client.request('threads', {})
  const list = (resp.body && resp.body.threads) || []
  session.threadId = list.length > 0 ? list[0].id : undefined
  return session.threadId
}

const ACTIONS = {
  sessions: async function () {
    if (!active) return { sessions: [] }
    return { sessions: [{ adapter: active.adapterId, program: active.program }] }
  },
  launch: async function (params, exec) {
    const s = await openSession(params, exec)
    return { ok: true, adapter: s.adapterId, program: s.program }
  },
  attach: async function (params, exec) {
    const s = await openAttach(params, exec)
    return { ok: true, adapter: s.adapterId, target: s.program }
  },
  terminate: async function () {
    if (!active) throw new Error('debug: no active session')
    try { await active.client.request('terminate', {}) } catch (e) { /* adapter may already be gone */ }
    active.client.close()
    active = null
    return { ok: true }
  },
  set_breakpoint: async function (params) {
    if (!active) throw new Error('debug: no active session')
    const file = params.file
    const line = params.line
    if (!file || !line) throw new Error('debug: set_breakpoint needs file and line')
    const bp = { line: Number(line) }
    if (params.condition) bp.condition = String(params.condition)
    if (params.function) bp.condition = bp.condition || String(params.function)
    const resp = await active.client.request('setBreakpoints', {
      source: { path: String(file) },
      breakpoints: [bp],
    })
    const created = (resp.body && resp.body.breakpoints) || []
    return { ok: true, breakpoints: created.map(function (b) { return { id: b.id, verified: b.verified, line: b.line, message: b.message || '' } }) }
  },
  remove_breakpoint: async function (params) {
    if (!active) throw new Error('debug: no active session')
    if (!params.file) throw new Error('debug: remove_breakpoint needs file')
    await active.client.request('setBreakpoints', { source: { path: String(params.file) }, breakpoints: [] })
    return { ok: true }
  },
  continue: async function () {
    if (!active) throw new Error('debug: no active session')
    const tid = await threadIdOf(active)
    if (tid === undefined) throw new Error('debug: no threads in session')
    const resp = await active.client.request('continue', { threadId: tid })
    const stopped = await waitForStopped(active.client, 3000)
    return {
      ok: true,
      allThreadsContinued: (resp.body && resp.body.allThreadsContinued) || false,
      stopped: stopped,
      note: stopped ? '' : 'no stopped event within 3s (program may have exited or be running)',
    }
  },
  step_over: async function () {
    if (!active) throw new Error('debug: no active session')
    const tid = await threadIdOf(active)
    if (tid === undefined) throw new Error('debug: no threads in session')
    await active.client.request('next', { threadId: tid })
    const stopped = await waitForStopped(active.client, 3000)
    return { ok: true, stopped: stopped }
  },
  step_in: async function () {
    if (!active) throw new Error('debug: no active session')
    const tid = await threadIdOf(active)
    if (tid === undefined) throw new Error('debug: no threads in session')
    await active.client.request('stepIn', { threadId: tid })
    const stopped = await waitForStopped(active.client, 3000)
    return { ok: true, stopped: stopped }
  },
  step_out: async function () {
    if (!active) throw new Error('debug: no active session')
    const tid = await threadIdOf(active)
    if (tid === undefined) throw new Error('debug: no threads in session')
    await active.client.request('stepOut', { threadId: tid })
    const stopped = await waitForStopped(active.client, 3000)
    return { ok: true, stopped: stopped }
  },
  pause: async function () {
    if (!active) throw new Error('debug: no active session')
    const tid = await threadIdOf(active)
    if (tid === undefined) throw new Error('debug: no threads in session')
    await active.client.request('pause', { threadId: tid })
    const stopped = await waitForStopped(active.client, 3000)
    return { ok: true, stopped: stopped }
  },
  threads: async function () {
    if (!active) throw new Error('debug: no active session')
    const resp = await active.client.request('threads', {})
    const list = (resp.body && resp.body.threads) || []
    if (list.length > 0) active.threadId = list[0].id
    return { threads: list }
  },
  stack_trace: async function (params) {
    if (!active) throw new Error('debug: no active session')
    const tid = await threadIdOf(active)
    if (tid === undefined) throw new Error('debug: no threads in session')
    const levels = params.levels || 20
    const resp = await active.client.request('stackTrace', { threadId: tid, startFrame: 0, levels: levels })
    return { stackFrames: ((resp.body && resp.body.stackFrames) || []).map(function (f) {
      return { id: f.id, name: f.name, line: f.line, column: f.column, source: f.source && f.source.path || '' }
    }) }
  },
  scopes: async function (params) {
    if (!active) throw new Error('debug: no active session')
    if (params.frame_id === undefined) throw new Error('debug: scopes needs frame_id')
    const resp = await active.client.request('scopes', { frameId: Number(params.frame_id) })
    return { scopes: ((resp.body && resp.body.scopes) || []).map(function (s) {
      return { name: s.name, variablesReference: s.variablesReference, expensive: !!s.expensive }
    }) }
  },
  variables: async function (params) {
    if (!active) throw new Error('debug: no active session')
    if (params.variable_ref === undefined) throw new Error('debug: variables needs variable_ref')
    const resp = await active.client.request('variables', { variablesReference: Number(params.variable_ref) })
    return { variables: ((resp.body && resp.body.variables) || []).map(function (v) {
      return { name: v.name, value: v.value, type: v.type || '', variablesReference: v.variablesReference || 0 }
    }) }
  },
  evaluate: async function (params) {
    if (!active) throw new Error('debug: no active session')
    if (!params.expression) throw new Error('debug: evaluate needs expression')
    const args = { expression: String(params.expression), context: params.context || 'watch' }
    if (params.frame_id !== undefined) args.frameId = Number(params.frame_id)
    const resp = await active.client.request('evaluate', args)
    const b = resp.body || {}
    return { result: b.result || '', type: b.type || '', variablesReference: b.variablesReference || 0 }
  },
  custom_request: async function (params) {
    if (!active) throw new Error('debug: no active session')
    if (!params.command) throw new Error('debug: custom_request needs command')
    const args = params.arguments !== undefined ? params.arguments : {}
    const resp = await active.client.request(String(params.command), args)
    return { command: params.command, body: resp.body !== undefined ? resp.body : null, message: resp.message || '' }
  },
  output: async function () {
    return { ok: true, note: 'output events are not buffered in v1' }
  },
}

function debugTool() {
  const actionNames = Object.keys(ACTIONS)
  const actionEnum = actionNames.slice()
  return defineTool({
    name: 'debug',
    description: 'Debugger access via DAP. Prefer over bash for program state, breakpoints, stepping, or thread inspection. ' +
      'One active session at a time. program is a target path, not a shell command. ' +
      'Flow: launch -> set_breakpoint (file, line) -> continue -> on stop inspect threads, stack_trace (frame_id), ' +
      'scopes (scope_id), variables (variable_ref) -> evaluate (expression, frame_id) -> terminate. ' +
      'Adapters auto-selected by extension: gdb (c/cpp/rust), lldb-dap, dlv (go), debugpy (python), ' +
      'js-debug-adapter (js/ts; needs nixpkgs vscode-js-debug). attach: pid (gdb) or host+port (debugpy). ' +
      'Read-only actions: ' + READONLY_ACTIONS.size + ' of the ' + actionNames.length + ' actions need no execution.',
    parameters: {
      action: { type: 'string', required: true, description: 'One of: ' + actionEnum.join(', ') },
      program: { type: 'string', description: 'Debug target path (required for launch).' },
      breakpoints: { type: 'array', items: { type: 'object', additionalProperties: true }, description: 'Breakpoints to set BEFORE launch: [{file, line, condition?}].' },
      args: { type: 'array', items: { type: 'string' }, description: 'Program arguments.' },
      adapter: { type: 'string', description: 'Adapter id override: gdb | lldb-dap | dlv | debugpy | js-debug-adapter.' },
      cwd: { type: 'string', description: 'Working directory for the debuggee.' },
      pid: { type: 'integer', description: 'Process id for attach (local).' },
      host: { type: 'string', description: 'Remote attach host (default 127.0.0.1).' },
      port: { type: 'integer', description: 'Remote attach port (uses debugpy adapter).' },
      file: { type: 'string', description: 'Source file for breakpoints.' },
      line: { type: 'integer', description: 'Source line for breakpoints.' },
      condition: { type: 'string', description: 'Breakpoint condition.' },
      expression: { type: 'string', description: 'Expression to evaluate.' },
      context: { type: 'string', description: 'Evaluate context: watch | repl | hover.' },
      frame_id: { type: 'integer', description: 'Stack frame id for scopes/evaluate.' },
      variable_ref: { type: 'integer', description: 'Variables reference from scopes/variables.' },
      levels: { type: 'integer', description: 'Max stack frames.' },
      command: { type: 'string', description: 'Raw DAP request command (custom_request).' },
      arguments: { type: 'object', additionalProperties: true, description: 'Raw DAP request arguments (custom_request).' },
    },
    output: {
      schema: { type: 'object', additionalProperties: true },
      render: function (_args, value) {
        return [{ type: 'text', text: JSON.stringify(value, null, 2) }]
      },
    },
    isConcurrencySafe: function () { return false },
    timeoutMs: 120000,
    async execute(args, exec) {
      const action = ACTIONS[args.action]
      if (!action) throw new Error('debug: unknown action ' + args.action)
      return await action(args, exec)
    },
  })
}

export function apply(ctx) {
  ctx.tools.register(debugTool())
  ctx.effect(function () {
    return function () {
      if (active) {
        try { active.client.close() } catch (e) { /* ignore */ }
        active = null
      }
    }
  }, name + ': shutdown')
}
