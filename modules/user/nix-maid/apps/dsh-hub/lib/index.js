/**
 * dsh-hub: supervised long-running processes (REPLs, watchers, dev servers).
 *
 * Ported from omp's hub tool (plan: docs/howto/agent-deferred.ru.md §6). A
 * process started with op:start lives between calls, its output is buffered
 * (bounded), stdin can be written with op:send, and it is cleaned up when the
 * plugin shuts down. Processes are scoped to the session that started them.
 */

import { spawn } from 'node:child_process'
import { defineTool } from '@deepseek-ai/dsh-tools'

export const name = 'dsh-hub'
export const inject = ['tools']

const MAX_BUFFER = 65536
const PROCS = new Map() // sessionId -> Map(procId -> entry)
let nextId = 1

function sessionKey(exec) {
  const sid = exec && exec.agent && exec.agent.session && exec.agent.session.id
  return sid || 'default'
}

function sessionCwd(exec) {
  const header = exec && exec.agent && exec.agent.session && exec.agent.session.header
  return (header && header.cwd) || process.cwd()
}

function appendBuffer(entry, chunk) {
  entry.buffer += String(chunk)
  if (entry.buffer.length > MAX_BUFFER) entry.buffer = entry.buffer.slice(-MAX_BUFFER)
}

function tableFor(sid) {
  let t = PROCS.get(sid)
  if (!t) { t = new Map(); PROCS.set(sid, t) }
  return t
}

function spawnProc(command, args, cwd) {
  const proc = spawn(command, args || [], { stdio: ['pipe', 'pipe', 'pipe'], cwd: cwd })
  const entry = {
    id: 'proc-' + nextId,
    command: command,
    args: args || [],
    proc: proc,
    buffer: '',
    startedAt: Date.now(),
    status: 'running',
    exitCode: null,
    exitedAt: null,
  }
  nextId += 1
  proc.stdout.on('data', function (d) { appendBuffer(entry, d) })
  proc.stderr.on('data', function (d) { appendBuffer(entry, d) })
  proc.on('error', function (err) {
    entry.status = 'error'
    entry.exitCode = null
    appendBuffer(entry, '\n[hub] spawn error: ' + String(err.message) + '\n')
  })
  proc.on('exit', function (code) {
    entry.status = 'exited'
    entry.exitCode = code
    entry.exitedAt = Date.now()
  })
  return entry
}

function summary(entry) {
  return {
    id: entry.id,
    command: entry.command,
    status: entry.status,
    exitCode: entry.exitCode,
    bytes: entry.buffer.length,
    startedAt: entry.startedAt,
  }
}

function tail(entry, max) {
  const t = entry.buffer
  return t.length > max ? '... [truncated ' + (t.length - max) + ' bytes]\n' + t.slice(-max) : t
}

function waitExit(entry, timeoutMs) {
  return new Promise(function (resolve) {
    if (entry.status !== 'running') return resolve(entry)
    const timer = setTimeout(function () { resolve(entry) }, timeoutMs)
    const check = setInterval(function () {
      if (entry.status !== 'running') {
        clearTimeout(timer)
        clearInterval(check)
        resolve(entry)
      }
    }, 50)
    entry.proc.once('exit', function () {
      clearTimeout(timer)
      clearInterval(check)
      resolve(entry)
    })
  })
}

const OPS = {
  start: async function (params, exec) {
    if (!params.command) throw new Error('hub: command is required')
    const sid = sessionKey(exec)
    const entry = spawnProc(String(params.command), Array.isArray(params.args) ? params.args : [], params.cwd || sessionCwd(exec))
    tableFor(sid).set(entry.id, entry)
    return summary(entry)
  },
  send: async function (params) {
    const entry = findEntry(params.id)
    if (entry.status !== 'running') throw new Error('hub: ' + params.id + ' is not running')
    entry.proc.stdin.write(String(params.input === undefined ? '' : params.input) + String.fromCharCode(10))
    return { ok: true, id: entry.id }
  },
  wait: async function (params) {
    const entry = findEntry(params.id)
    const timeoutMs = params.timeout_ms || 30000
    const e = await waitExit(entry, timeoutMs)
    return { id: e.id, status: e.status, exitCode: e.exitCode, output: tail(e, 8000) }
  },
  stop: async function (params) {
    const entry = findEntry(params.id)
    try { entry.proc.kill('SIGTERM') } catch (e) { /* ignore */ }
    await waitExit(entry, 3000)
    if (entry.status === 'running') {
      try { entry.proc.kill('SIGKILL') } catch (e) { /* ignore */ }
      await waitExit(entry, 2000)
    }
    return { id: entry.id, status: entry.status, exitCode: entry.exitCode, output: tail(entry, 8000) }
  },
  list: async function (params, exec) {
    const sid = sessionKey(exec)
    const t = tableFor(sid)
    return { processes: Array.from(t.values()).map(function (e) { return summary(e) }) }
  },
}

function findEntry(id) {
  const sid = PROCS.size === 0 ? null : null
  for (const t of PROCS.values()) {
    const e = t.get(id)
    if (e) return e
  }
  throw new Error('hub: no such process ' + id)
}

function hubTool() {
  const opNames = Object.keys(OPS)
  return defineTool({
    name: 'hub',
    description: 'Supervise long-running processes (REPLs, watchers, dev servers). ' +
      'Processes live between calls; output is buffered. Ops: ' + opNames.join(', ') + '. ' +
      'start: command + args (no shell). send: write a line to stdin. wait: block until exit ' +
      'or timeout. stop: terminate. list: show session processes.',
    parameters: {
      op: { type: 'string', required: true, description: 'One of: ' + opNames.join(', ') },
      command: { type: 'string', description: 'Binary to start (required for op=start).' },
      args: { type: 'array', items: { type: 'string' }, description: 'Arguments for the process.' },
      cwd: { type: 'string', description: 'Working directory (default session cwd).' },
      id: { type: 'string', description: 'Process id (from start/list).' },
      input: { type: 'string', description: 'Line to write to stdin (op=send).' },
      timeout_ms: { type: 'integer', description: 'Wait timeout in ms (default 30000).' },
    },
    output: {
      schema: { type: 'object', additionalProperties: true },
      render: function (_a, v) {
        return [{ type: 'text', text: JSON.stringify(v, null, 2) }]
      },
    },
    isConcurrencySafe: function () { return false },
    timeoutMs: 60000,
    async execute(args, exec) {
      const op = OPS[args.op]
      if (!op) throw new Error('hub: unknown op ' + args.op)
      return await op(args, exec)
    },
  })
}

export function apply(ctx) {
  ctx.tools.register(hubTool())
  ctx.effect(function () {
    return function () {
      PROCS.forEach(function (t) {
        t.forEach(function (e) {
          try { e.proc.kill('SIGKILL') } catch (err) { /* ignore */ }
        })
      })
      PROCS.clear()
    }
  }, name + ': shutdown')
}
