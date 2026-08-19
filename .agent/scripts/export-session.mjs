#!/usr/bin/env node
/**
 * dsh-export-session: render a dsh session (session.jsonl.zstd) into a
 * standalone HTML transcript (ported from omp export idea; plan
 * docs/howto/agent-deferred.ru.md §8).
 *
 * Usage: node export-session.mjs <session-id-or-path> [out.html]
 * Looks up ~/.dsh/sessions/<project>/<id>/session.jsonl.zstd, decompresses
 * with zstd, parses known event types, renders chat + tool cards.
 */

import { execFileSync } from 'node:child_process'
import { readdirSync, existsSync, readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { homedir } from 'node:os'

const SESSIONS_ROOT = join(homedir(), '.dsh', 'sessions')

function findSessionPath(idOrPath) {
  if (existsSync(idOrPath)) {
    const p = idOrPath
    if (p.endsWith('.zstd') && existsSync(p)) return p
    if (existsSync(join(p, 'session.jsonl.zstd'))) return join(p, 'session.jsonl.zstd')
  }
  for (const project of readdirSync(SESSIONS_ROOT)) {
    const proj = join(SESSIONS_ROOT, project)
    if (!existsSync(proj)) continue
    for (const sid of readdirSync(proj)) {
      const cand = join(proj, sid, 'session.jsonl.zstd')
      if (existsSync(cand) && (sid === idOrPath || sid.indexOf(idOrPath) === 0)) return cand
    }
  }
  return null
}

function decompress(path) {
  return execFileSync('zstd', ['-d', '-c', path], { maxBuffer: 64 * 1024 * 1024 }).toString('utf8')
}

function textOf(msg) {
  const blocks = msg && msg.content
  if (Array.isArray(blocks)) {
    return blocks.map(function (b) { return (b && typeof b.text === 'string') ? b.text : '' }).join('\n')
  }
  if (msg && typeof msg.text === 'string') return msg.text
  return ''
}

function esc(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
}

function render(events) {
  const parts = []
  for (const ev of events) {
    if (ev.type === 'user/message' || ev.type === 'assistant/message') {
      const who = ev.type === 'user/message' ? 'user' : 'assistant'
      const t = textOf(ev.data)
      if (t === '') continue
      parts.push('<div class=\"msg ' + who + '\"><div class=\"who\">' + who + '</div><pre>' + esc(t) + '</pre></div>')
    } else if (ev.type === 'tool/call') {
      const name = ev.data && ev.data.name
      const args = ev.data && typeof ev.data.arguments === 'string' ? ev.data.arguments : JSON.stringify(ev.data && ev.data.arguments || {})
      parts.push('<details class=\"tool\"><summary>tool: ' + esc(name || '?') + '</summary><pre>' + esc(args.slice(0, 2000)) + '</pre></details>')
    } else if (ev.type === 'tool/result') {
      const txt = textOf(ev.data && ev.data.message) || ''
      parts.push('<details class=\"toolres\"><summary>result</summary><pre>' + esc(txt.slice(0, 2000)) + '</pre></details>')
    }
  }
  return parts.join('\n')
}

const target = process.argv[2]
const outPath = process.argv[3] || 'session-export.html'
if (!target) {
  console.error('usage: node export-session.mjs <session-id|path> [out.html]')
  process.exit(1)
}
const path = findSessionPath(target)
if (!path) {
  console.error('session not found: ' + target + ' (searched ' + SESSIONS_ROOT + ')')
  process.exit(1)
}
const raw = decompress(path)
const events = raw.split('\n').map(function (l) {
  try { return JSON.parse(l) } catch (e) { return null }
}).filter(Boolean)
const body = render(events)
const html = '<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>dsh session export</title>' +
  '<style>body{font-family:system-ui,sans-serif;max-width:900px;margin:2rem auto;padding:0 1rem;color:#222}' +
  '.msg{border:1px solid #ddd;border-radius:8px;padding:10px 14px;margin:8px 0}' +
  '.user{background:#f3f6fb}.assistant{background:#fff}' +
  '.who{font-size:12px;color:#888;margin-bottom:4px}pre{white-space:pre-wrap;word-break:break-word;margin:0;font-family:ui-monospace,monospace;font-size:13px}' +
  'details.tool{border:1px dashed #bbb;border-radius:6px;padding:6px 10px;margin:4px 0;font-size:12px}' +
  '</style></head><body><h1>dsh session export</h1><p>session: ' + esc(path) + ' — ' + events.length + ' events</p>' +
  body + '</body></html>'
writeFileSync(outPath, html)
console.log('wrote ' + outPath + ' (' + html.length + ' bytes, ' + events.length + ' events)')
