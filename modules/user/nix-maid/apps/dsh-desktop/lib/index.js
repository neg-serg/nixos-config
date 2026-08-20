/**
 * dsh-desktop: Linux desktop control for DSH (backlog plan:
 * docs/howto/agent-backlog-research.ru.md §3), backed by computer-use-linux
 * (CUL) + grim on Hyprland.
 *
 * Tool `desktop` actions:
 *   doctor       — CUL readiness report (JSON).
 *   windows      — window list (hyprctl backend).
 *   screenshot   — grim capture of the whole screen; returns the PNG path
 *                  for describe_image/read_image (vision chain stays local).
 *   apps         — AT-SPI app list (needs org.a11y.Bus).
 *   click/type/scroll — MCP bridge to CUL (semantic selectors or pixels);
 *                  only ever runs when explicitly called.
 * Config: { culBin? } — binary path override (default resolves
 * ~/.local/bin → /run/current-system/sw/bin → PATH).
 */

import { spawn } from 'node:child_process'
import { existsSync } from 'node:fs'
import { join } from 'node:path'
import { defineTool } from '@deepseek-ai/dsh-tools'

export const name = 'dsh-desktop'

export const inject = ['tools']

const NL = String.fromCharCode(10)

/** Resolve a binary like dsh-lsp does: ~/.local/bin → sw/bin → PATH. */
function resolveBin(name) {
  const home = process.env.HOME || '/home/neg'
  const cands = [
    join(home, '.local', 'bin', name),
    join('/run/current-system/sw/bin', name),
  ]
  for (const c of cands) if (existsSync(c)) return c
  return name
}

/** Minimal MCP client over stdio (JSON-RPC, newline-delimited). */
class McpClient {
  constructor(bin) {
    this.bin = bin
    this.proc = null
    this.buf = ''
    this.nextId = 1
    this.pending = new Map()
  }
  start() {
    this.proc = spawn(this.bin, ['mcp'], { stdio: ['pipe', 'pipe', 'pipe'] })
    this.proc.stdout.setEncoding('utf8')
    this.proc.stdout.on('data', (chunk) => {
      this.buf += chunk
      let idx
      while ((idx = this.buf.indexOf('\n')) !== -1) {
        const line = this.buf.slice(0, idx).trim()
        this.buf = this.buf.slice(idx + 1)
        if (line === '') continue
        let msg
        try { msg = JSON.parse(line) } catch { continue }
        if (msg.id !== undefined) {
          const p = this.pending.get(msg.id)
          if (p) { this.pending.delete(msg.id); msg.error ? p.reject(new Error(msg.error.message || 'MCP error')) : p.resolve(msg.result) }
        }
      }
    })
  }
  request(method, params) {
    return new Promise((resolve, reject) => {
      if (!this.proc) this.start()
      const id = this.nextId++
      const timer = setTimeout(() => { if (this.pending.has(id)) { this.pending.delete(id); reject(new Error('MCP timeout: ' + method)) } }, 15000)
      this.pending.set(id, { resolve: (v) => { clearTimeout(timer); resolve(v) }, reject: (e) => { clearTimeout(timer); reject(e) } })
      this.proc.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params: params || {} }) + '\n')
    })
  }
  notify(method, params) {
    this.proc.stdin.write(JSON.stringify({ jsonrpc: '2.0', method, params: params || {} }) + '\n')
  }
  async init() {
    await this.request('initialize', { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'dsh-desktop', version: '0.1.0' } })
    this.notify('notifications/initialized', {})
  }
  async callTool(name, args) {
    const r = await this.request('tools/call', { name: name, arguments: args || {} })
    const content = r && Array.isArray(r.content) ? r.content : []
    return content.map(function (b) { return (b && typeof b.text === 'string') ? b.text : '' }).join(NL)
  }
  stop() { if (this.proc) { try { this.proc.kill() } catch {} this.proc = null } }
}

/** Grim whole-screen capture; returns the saved PNG path. */
async function grimCapture() {
  const { execFile } = await import('node:child_process')
  const grim = resolveBin('grim')
  const path = '/tmp/dsh-desktop-' + Date.now() + '.png'
  await new Promise((resolve, reject) => {
    execFile(grim, [path], { timeout: 15000 }, (err) => err ? reject(new Error('grim: ' + (err.message || err))) : resolve())
  })
  return path
}

const desktopTool = defineTool({
  name: 'desktop',
  description: 'Linux desktop control: doctor (readiness), windows (hyprctl list), screenshot (grim PNG path for describe_image/read_image), apps (AT-SPI), click/type/scroll (MCP bridge to computer-use-linux; explicit calls only).',
  parameters: {
    action: { type: 'string', required: true, description: 'One of: doctor, windows, screenshot, apps, click, type, scroll' },
    selector: { type: 'string', description: 'Semantic selector (element name) for click/type.' },
    text: { type: 'string', description: 'Text to type (type action).' },
    x: { type: 'number', description: 'X coordinate (click/scroll pixel fallback).' },
    y: { type: 'number', description: 'Y coordinate (click/scroll pixel fallback).' },
    deltaY: { type: 'number', description: 'Scroll deltaY.' },
  },
  output: { schema: { type: 'string' }, render: (_a, v) => [{ type: 'text', text: v }] },
  isConcurrencySafe: () => true,
  timeoutMs: 30000,
  async execute(args, exec) {
    const cfg = (exec && exec.agent && exec.agent.config) || {}
    const culBin = (cfg && cfg.culBin) || resolveBin('computer-use-linux')
    const json = function (v) { return JSON.stringify(v) }
    const action = String(args.action || '')
    if (action === 'screenshot') {
      const path = await grimCapture()
      return json({ path: path, hint: 'Inspect with describe_image or read_image' })
    }
    const { execFile } = await import('node:child_process')
    const runCli = function (sub) {
      return new Promise((resolve, reject) => {
        execFile(culBin, [sub], { timeout: 15000, maxBuffer: 4 * 1024 * 1024 }, (err, stdout) => err ? reject(new Error(String(err.message || err).slice(0, 300))) : resolve(String(stdout || '').trim()))
      })
    }
    if (action === 'doctor') return await runCli('doctor')
    if (action === 'windows') return await runCli('windows')
    if (action === 'apps') return await runCli('apps')
    if (action === 'click' || action === 'type' || action === 'scroll') {
      const mcp = new McpClient(culBin)
      try {
        await mcp.init()
        let params = {}
        if (action === 'click') params = args.x !== undefined ? { x: Number(args.x), y: Number(args.y) } : (args.selector ? { name: String(args.selector) } : {})
        if (action === 'type') params = { text: String(args.text || ''), ...(args.selector ? { name: String(args.selector) } : {}) }
        if (action === 'scroll') params = { x: Number(args.x) || 0, y: Number(args.y) || 0, deltaY: Number(args.deltaY) || 0 }
        return await mcp.callTool(action, params)
      } finally { mcp.stop() }
    }
    throw new Error('desktop: unknown action ' + action)
  },
})

export function apply(ctx) {
  ctx.tools.register(desktopTool)
}
