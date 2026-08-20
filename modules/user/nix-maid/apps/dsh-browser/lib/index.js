/**
 * dsh-browser: CDP browser control for DSH (backlog plan:
 * docs/howto/agent-backlog-research.ru.md §2).
 *
 * Speaks Chrome DevTools Protocol over the BROWSER WebSocket (works on both
 * Vivaldi and headless chromium): every page action creates a NEW dedicated
 * target via Target.createTarget + attachToTarget; user tabs are untouched.
 * NOTE: Vivaldi's CDP answers browser-level commands but silences page
 * domains — full page automation needs the dedicated headless chromium
 * service on :9223 (dsh-browser.nix).
 *
 * Tool `browser` actions: list_targets, navigate(url), extract_text(),
 * screenshot(), click(selector), type(selector, text), close_target().
 * Config: { endpoint? } (default http://127.0.0.1:9222).
 */

import { defineTool } from '@deepseek-ai/dsh-tools'

export const name = 'dsh-browser'

export const inject = ['tools']

const DEFAULT_ENDPOINT = 'http://127.0.0.1:9222'

/** CDP client over the browser-level WebSocket, with page sessions. */
class CdpClient {
  constructor(wsUrl) {
    this.wsUrl = wsUrl
    this.ws = null
    this.nextId = 1
    this.pending = new Map()
  }
  async connect() {
    if (this.ws && this.ws.readyState === 1) return
    await new Promise((resolve, reject) => {
      const ws = new WebSocket(this.wsUrl)
      ws.onopen = resolve
      ws.onerror = () => reject(new Error('CDP connect failed'))
      this.ws = ws
    })
    this.ws.onmessage = (ev) => {
      let msg
      try { msg = JSON.parse(String(ev.data)) } catch { return }
      if (msg.id !== undefined) {
        const p = this.pending.get(msg.id)
        if (p) { this.pending.delete(msg.id); msg.error ? p.reject(new Error(msg.error.message)) : p.resolve(msg.result) }
      }
    }
  }
  send(method, params, sessionId) {
    const id = this.nextId++
    return new Promise(async (resolve, reject) => {
      await this.connect().catch(reject)
      const timer = setTimeout(() => {
        if (this.pending.has(id)) { this.pending.delete(id); reject(new Error('CDP timeout: ' + method)) }
      }, 10000)
      this.pending.set(id, { resolve: (v) => { clearTimeout(timer); resolve(v) }, reject: (e) => { clearTimeout(timer); reject(e) } })
      this.ws.send(JSON.stringify({ id, method, params: params || {}, ...(sessionId ? { sessionId } : {}) }))
    })
  }
  async createTarget(url) {
    const { targetId } = await this.send('Target.createTarget', { url: url || 'about:blank' })
    const { sessionId } = await this.send('Target.attachToTarget', { targetId, flatten: true })
    return { targetId, sessionId }
  }
  async attachTarget(targetId) {
    const { sessionId } = await this.send('Target.attachToTarget', { targetId, flatten: true })
    return { targetId, sessionId }
  }
  async closeTarget(targetId) {
    try { await this.send('Target.closeTarget', { targetId }) } catch {}
  }
  close() { if (this.ws) { try { this.ws.close() } catch {} this.ws = null } }
}

async function browserWsUrl(endpoint) {
  const res = await fetch(endpoint + '/json/version')
  if (!res.ok) throw new Error('CDP /json/version HTTP ' + res.status)
  const v = await res.json()
  if (!v || !v.webSocketDebuggerUrl) throw new Error('CDP endpoint has no browser ws url')
  return v.webSocketDebuggerUrl
}

async function listTargets(endpoint) {
  const res = await fetch(endpoint + '/json')
  if (!res.ok) throw new Error('CDP /json HTTP ' + res.status)
  const list = await res.json()
  return Array.isArray(list) ? list.map(function (t) { return { id: t.id, type: t.type, title: t.title, url: t.url } }) : []
}

function jsString(s) { return JSON.stringify(String(s)) }

async function evaluate(cdp, sessionId, expression) {
  const r = await cdp.send('Runtime.evaluate', { expression: expression, returnByValue: true }, sessionId)
  if (r && r.exceptionDetails) throw new Error('page eval: ' + (r.exceptionDetails.text || 'exception'))
  return r ? r.result && r.result.value : undefined
}

const browserTool = defineTool({
  name: 'browser',
  description: 'Control a dedicated CDP browser tab (headless chromium :9223 or Vivaldi :9222). Actions: list_targets, navigate(url), extract_text(), screenshot(), click(selector), type(selector, text), close_target(targetId). Works on a private tab only; user tabs are untouched. For human-like GUI interaction with a site prefer the desktop tool; browser is for programmatic DOM/JS access.',
  parameters: {
    action: { type: 'string', required: true, description: 'One of: list_targets, navigate, extract_text, screenshot, click, type, close_target' },
    url: { type: 'string', description: 'URL for navigate (http/https/data).' },
    targetId: { type: 'string', description: 'Target id for close_target.' },
    selector: { type: 'string', description: 'CSS selector for click/type.' },
    text: { type: 'string', description: 'Text to type into the element (type action).' },
  },
  output: { schema: { type: 'string' }, render: (_a, v) => [{ type: 'text', text: v }] },
  isConcurrencySafe: () => true,
  timeoutMs: 30000,
  async execute(args, exec) {
    const cfg = (exec && exec.agent && exec.agent.config) || {}
    const endpoint = (cfg && cfg.endpoint) || DEFAULT_ENDPOINT
    const json = function (v) { return JSON.stringify(v) }
    const action = String(args.action || '')
    if (action === 'list_targets') return json({ targets: await listTargets(endpoint) })
    if (action === 'close_target') {
      if (!args.targetId) throw new Error('browser: close_target needs targetId')
      const cdp = new CdpClient(await browserWsUrl(endpoint))
      try { await cdp.closeTarget(String(args.targetId)) } finally { cdp.close() }
      return json({ closed: String(args.targetId) })
    }
    const cdp = new CdpClient(await browserWsUrl(endpoint))
    try {
      // Reuse the caller's tab (targetId) or open a fresh dedicated one.
      const { targetId, sessionId } = args.targetId
        ? await cdp.attachTarget(String(args.targetId))
        : await cdp.createTarget('about:blank')
      await cdp.send('Page.enable', {}, sessionId)
      if (action === 'navigate') {
        await cdp.send('Page.navigate', { url: String(args.url) }, sessionId)
        await new Promise((r) => setTimeout(r, 2000))
        return json({ targetId: targetId, url: String(args.url) })
      }
      if (action === 'extract_text') {
        const text = await evaluate(cdp, sessionId, 'document.body ? document.body.innerText : \'\'')
        return json({ targetId: targetId, text: String(text || '') })
      }
      if (action === 'screenshot') {
        const shot = await cdp.send('Page.captureScreenshot', { format: 'png' }, sessionId)
        return json({ targetId: targetId, data: shot && shot.data ? shot.data : '' })
      }
      if (action === 'click') {
        if (!args.selector) throw new Error('browser: click needs selector')
        const ok = await evaluate(cdp, sessionId, '(function(){var el=document.querySelector(' + jsString(args.selector) + '); if(!el) return false; el.click(); return true})()')
        return json({ targetId: targetId, clicked: ok === true })
      }
      if (action === 'type') {
        if (!args.selector || args.text === undefined) throw new Error('browser: type needs selector and text')
        const ok = await evaluate(cdp, sessionId, '(function(){var el=document.querySelector(' + jsString(args.selector) + '); if(!el) return false; var s=' + jsString(String(args.text)) + '; var proto=el.tagName===\'TEXTAREA\'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype; var set=Object.getOwnPropertyDescriptor(proto,\'value\').set; set.call(el,s); el.dispatchEvent(new Event(\'input\',{bubbles:true})); el.dispatchEvent(new Event(\'change\',{bubbles:true})); return true})()')
        return json({ targetId: targetId, typed: ok === true })
      }
      throw new Error('browser: unknown action ' + action)
    } finally {
      cdp.close()
    }
  },
})

export function apply(ctx) {
  ctx.tools.register(browserTool)
}
