/**
 * dsh-eval: persistent code kernels (Python / Bun). State survives across calls
 * and subagents; reset clears it; a crashed kernel is restarted with a clean
 * namespace and an explicit notice.
 *
 * Ported from omp's eval tool (plan: docs/howto/agent-deferred.ru.md §2). v1:
 * serial cells only (no parallel(thunks)); line-delimited JSON protocol to the
 * kernel process.
 */

import { spawn } from 'node:child_process'
import { existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { defineTool } from '@deepseek-ai/dsh-tools'

export const name = 'dsh-eval'
export const inject = ['tools']

const NL = String.fromCharCode(10)
const KERNELS = new Map() // sessionId -> { proc, type, cwd, pending, buf, nextId }

function kernelScript(file) {
  return fileURLToPath(new URL(file, import.meta.url))
}

function resolveBun() {
  const home = process.env.HOME || ''
  const candidates = [
    home + '/.bun/bin/bun',
    home + '/.cache/.bun/bin/bun',
    '/run/current-system/sw/bin/bun',
    '/usr/local/bin/bun',
  ]
  for (const p of candidates) {
    try {
      if (existsSync(p)) return p
    } catch (e) { /* keep probing */ }
  }
  return 'bun' // rely on PATH
}

function spawnKernel(type, cwd) {
  if (type === 'python') {
    return spawn('python3', [kernelScript('kernel.py')], { stdio: ['pipe', 'pipe', 'pipe'], cwd: cwd })
  }
  return spawn(resolveBun(), ['run', kernelScript('kernel.js')], { stdio: ['pipe', 'pipe', 'pipe'], cwd: cwd })
}

function sessionCwd(exec) {
  const header = exec && exec.agent && exec.agent.session && exec.agent.session.header
  return (header && header.cwd) || process.cwd()
}

function sessionId(exec) {
  const sid = exec && exec.agent && exec.agent.session && exec.agent.session.id
  return sid || 'default'
}

function killKernel(sid) {
  const k = KERNELS.get(sid)
  if (!k) return
  try { k.proc.kill('SIGKILL') } catch (e) { /* ignore */ }
  try { k.proc.stdin.end() } catch (e) { /* ignore */ }
  KERNELS.delete(sid)
}

function drain(k) {
  let idx = k.buf.indexOf(NL)
  while (idx >= 0) {
    const line = k.buf.slice(0, idx).trim()
    k.buf = k.buf.slice(idx + 1)
    if (line) {
      let msg = null
      try { msg = JSON.parse(line) } catch (e) { msg = null }
      if (msg && msg.id !== undefined) {
        const p = k.pending.get(msg.id)
        if (p) {
          k.pending.delete(msg.id)
          p.resolve(msg)
        }
      }
    }
    idx = k.buf.indexOf(NL)
  }
}

function ensureKernel(type, cwd, sid) {
  let k = KERNELS.get(sid)
  if (k && k.type !== type) {
    killKernel(sid)
    k = null
  }
  if (!k) {
    const proc = spawnKernel(type, cwd)
    k = { proc: proc, type: type, cwd: cwd, pending: new Map(), buf: '', nextId: 0 }
    proc.stdout.on('data', function (d) {
      k.buf += String(d)
      drain(k)
    })
    proc.on('exit', function () {
      const err = new Error('eval kernel exited (state lost); next call restarts it')
      k.pending.forEach(function (p) { p.reject(err) })
      k.pending.clear()
      KERNELS.delete(sid)
    })
    KERNELS.set(sid, k)
  }
  return k
}

function runCode(k, code, reset, timeoutMs) {
  k.nextId += 1
  const id = k.nextId
  const payload = JSON.stringify({ id: id, code: String(code || ''), reset: !!reset })
  const self = k
  return new Promise(function (resolve, reject) {
    const timer = setTimeout(function () {
      if (self.pending.has(id)) {
        self.pending.delete(id)
        reject(new Error('eval: kernel timed out after ' + timeoutMs + 'ms'))
      }
    }, timeoutMs)
    self.pending.set(id, {
      resolve: function (m) { clearTimeout(timer); resolve(m) },
      reject: function (e) { clearTimeout(timer); reject(e) },
    })
    try {
      self.proc.stdin.write(payload + NL)
    } catch (e) {
      self.pending.delete(id)
      clearTimeout(timer)
      reject(new Error('eval: kernel not writable (crashed?)'))
    }
  })
}

function evalTool() {
  return defineTool({
    name: 'eval',
    description: 'Run code in a persistent kernel. State survives across calls and subagents. ' +
      'Work incrementally: imports, define, test, use — each its own call. Use reset to clear ' +
      'the namespace. A crashed kernel restarts clean on the next call. v1: serial cells only.',
    parameters: {
      kernel: { type: 'string', description: 'python (default) or bun.' },
      code: { type: 'string', required: true, description: 'Code to execute in the persistent namespace.' },
      reset: { type: 'boolean', description: 'Clear the namespace before running (default false).' },
      timeout: { type: 'integer', description: 'Timeout ms (default 60000).' },
    },
    output: {
      schema: { type: 'object', additionalProperties: true },
      render: function (_a, v) {
        return [{ type: 'text', text: (v.ok ? '' : 'ERROR: ') + String(v.stdout || '') + (v.error ? '\n' + v.error : '') }]
      },
    },
    isConcurrencySafe: function () { return false },
    timeoutMs: 120000,
    async execute(args, exec) {
      const type = args.kernel === 'bun' ? 'bun' : 'python'
      const sid = sessionId(exec)
      const cwd = sessionCwd(exec)
      const k = ensureKernel(type, cwd, sid)
      const resp = await runCode(k, args.code, args.reset, args.timeout || 60000)
      return { ok: resp.ok, stdout: resp.stdout || '', error: resp.error || null }
    },
  })
}

export function apply(ctx) {
  ctx.tools.register(evalTool())
  ctx.effect(function () {
    return function () {
      KERNELS.forEach(function (k, sid) { killKernel(sid) })
    }
  }, name + ': shutdown')
}
