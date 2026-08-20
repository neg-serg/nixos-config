#!/usr/bin/env node
/**
 * code-review: local git-diff review via an Ollama model (autoresearch toolset).
 *
 * Reads a unified diff (stdin or --diff FILE) and asks the model for issues,
 * returning the raw review plus a short JSON summary.
 *
 * Usage: git diff | node code-review.mjs [--model MODEL] [--max-chars N]
 *        node code-review.mjs --diff /tmp/d.patch [--model qwen3:8b-q8_0]
 */

import { readFileSync } from 'node:fs'

const NL = String.fromCharCode(10)
const ENDPOINT = 'http://127.0.0.1:11434/api/chat'
const DEFAULT_MODEL = 'qwen3:8b-q8_0'

const SYSTEM = 'Ты — строгий ревьюер кода. Получаешь git diff. Найди: баги и логические ошибки, проблемы безопасности, отсутствующие проверки, очевидные стилевые проблемы. Для каждого замечания строка формата: - [severity] файл:строка: сообщение. severity: high | medium | low. Если замечаний нет — ответь ровно OK. Не хвали, не пересказывай дифф, не пиши лишнего текста.'

function parseArgs(argv) {
  const out = { maxChars: 8000 }
  for (let i = 0; i < argv.length; i += 2) {
    const key = argv[i]
    if (!key || !key.startsWith('--')) { i -= 1; continue }
    const val = argv[i + 1]
    if (key === '--max-chars') out.maxChars = Number(val) > 0 ? Number(val) : out.maxChars
    else out[key.slice(2)] = val
  }
  return out
}

function countIssues(text) {
  const re = /- \[?(high|medium|low)\]?/gi
  let n = 0, m
  while ((m = re.exec(text)) !== null) n += 1
  return n
}

async function main() {
  const a = parseArgs(process.argv.slice(2))
  const model = a.model || DEFAULT_MODEL
  let diff = ''
  if (a.diff) {
    diff = readFileSync(a.diff, 'utf8')
  } else {
    process.stdin.setEncoding('utf8')
    for await (const chunk of process.stdin) diff += chunk
  }
  if (diff.trim() === '') { console.error('code-review: empty diff (pipe git diff or pass --diff)'); process.exit(1) }
  const bounded = diff.slice(0, a.maxChars)
  const t0 = Date.now()
  const res = await fetch(ENDPOINT, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      model,
      stream: false,
      options: { temperature: 0.1 },
      messages: [
        { role: 'system', content: SYSTEM },
        { role: 'user', content: 'Git diff:\n' + bounded + (bounded.length < diff.length ? '\n[truncated]' : '') },
      ],
    }),
  })
  if (!res.ok) throw new Error('ollama HTTP ' + res.status)
  const data = await res.json()
  const review = (data && data.message ? String(data.message.content || '') : '').trim()
  const issues = countIssues(review)
  console.log('=== review (' + model + ', ' + Math.round((Date.now() - t0) / 1000) + 's, issues=' + issues + ') ===')
  console.log(review)
  if (a.out) {
    const fs = await import('node:fs')
    fs.writeFileSync(a.out, JSON.stringify({ model, issues, review }, null, 2))
    console.log('report written to ' + a.out)
  }
}

main().catch(function (e) { console.error('code-review: ' + e); process.exit(1) })
