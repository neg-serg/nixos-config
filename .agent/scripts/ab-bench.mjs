#!/usr/bin/env node
/**
 * ab-bench: A/B prompt bench over local Ollama models (autoresearch proto).
 *
 * Runs every preset (system prompt + model + temperature) on every task,
 * then a pairwise judge model picks the better answer per task per pair,
 * scoring wins/ties/losses per preset.
 *
 * Usage: node ab-bench.mjs [--tasks FILE.json] [--presets FILE.json]
 *                          [--judge MODEL] [--out FILE.json]
 * Defaults: built-in demo tasks/presets, judge qwen3:8b-q8_0.
 * Task:     { id, prompt }
 * Preset:   { id, system, model, temperature? } (temperature default 0.2)
 * Output:   JSON report (responses, verdicts, scores) and a summary table.
 */

import { readFileSync, writeFileSync } from 'node:fs'

const NL = String.fromCharCode(10)
const ENDPOINT = 'http://127.0.0.1:11434/api/chat'
const DEFAULT_JUDGE = 'qwen3:8b-q8_0'

const DEMO_TASKS = [
  { id: 'freq', prompt: 'Напиши функцию на Python, которая считает частоту слов в тексте.' },
  { id: 'mixin', prompt: 'Объясни разницу между миксинами и композицией в Python за 2-3 предложения.' },
  { id: 'nh', prompt: 'Что делает команда: nh os switch /etc/nixos#odin --option substitute false? Ответь коротко.' },
]

const DEMO_PRESETS = [
  { id: 'terse', system: 'Отвечай кратко, по делу, без предисловий.', model: 'qwen3:8b-q8_0', temperature: 0.2 },
  { id: 'detailed', system: 'Отвечай подробно и структурированно: объясни шаги, приведи пример, укажи ограничения.', model: 'qwen3:8b-q8_0', temperature: 0.2 },
]

/** Judge rubric: strict JSON verdict. */
const JUDGE_SYSTEM = 'Ты — жюри A/B-теста. Получаешь задачу и два ответа (A и B). Оцени, какой ответ лучше по критериям: правильность, полнота, ясность, соответствие запросу. Верни СТРОГО JSON без markdown и пояснений: {\"winner\": \"a\" | \"b\" | \"tie\", \"reason\": \"кратко почему\"}.'

function parseArgs(argv) {
  const out = {}
  for (let i = 0; i < argv.length; i += 2) {
    const key = argv[i]
    if (!key || !key.startsWith('--')) { i -= 1; continue }
    out[key.slice(2)] = argv[i + 1]
  }
  return out
}

function loadJson(path, fallback, label) {
  if (!path) return fallback
  try { return JSON.parse(readFileSync(path, 'utf8')) }
  catch (e) { console.error('ab-bench: cannot load ' + label + ' from ' + path + ': ' + e); process.exit(1) }
}

function parseJson(text) {
  let t = String(text || '').trim()
  const f = t.match(/```(?:json)?\s*([\s\S]*?)```/)
  if (f) t = f[1].trim()
  try { return JSON.parse(t) }
  catch {
    const s = t.indexOf('{'), e = t.lastIndexOf('}')
    if (s !== -1 && e > s) { try { return JSON.parse(t.slice(s, e + 1)) } catch {} }
    return null
  }
}

async function chat(model, system, user, temperature) {
  const res = await fetch(ENDPOINT, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      model,
      stream: false,
      options: { temperature: Number(temperature) || 0.2 },
      messages: [
        { role: 'system', content: system },
        { role: 'user', content: user },
      ],
    }),
  })
  if (!res.ok) throw new Error('ollama HTTP ' + res.status + ' for ' + model)
  const data = await res.json()
  return data && data.message ? String(data.message.content || '') : ''
}

async function main() {
  const a = parseArgs(process.argv.slice(2))
  const tasks = loadJson(a.tasks, DEMO_TASKS, 'tasks')
  const presets = loadJson(a.presets, DEMO_PRESETS, 'presets')
  const judge = a.judge || DEFAULT_JUDGE
  if (!Array.isArray(tasks) || tasks.length === 0) { console.error('ab-bench: no tasks'); process.exit(1) }
  if (!Array.isArray(presets) || presets.length < 2) { console.error('ab-bench: need >= 2 presets'); process.exit(1) }

  // 1) responses
  const responses = {}
  for (const task of tasks) {
    responses[task.id] = responses[task.id] || {}
    for (const p of presets) {
      process.stdout.write('  run ' + p.id + ' on ' + task.id + ' ... ')
      const t0 = Date.now()
      try {
        responses[task.id][p.id] = { text: await chat(p.model, p.system, task.prompt, p.temperature), ms: Date.now() - t0 }
        console.log('ok (' + Math.round((Date.now() - t0) / 1000) + 's)')
      } catch (e) {
        responses[task.id][p.id] = { text: '', ms: Date.now() - t0, error: String(e) }
        console.log('ERROR ' + e)
      }
    }
  }

  // 2) pairwise judging
  const verdicts = []
  for (const task of tasks) {
    for (let i = 0; i < presets.length; i++) {
      for (let j = i + 1; j < presets.length; j++) {
        const pa = presets[i], pb = presets[j]
        const ra = responses[task.id][pa.id] || { text: '' }
        const rb = responses[task.id][pb.id] || { text: '' }
        if (ra.error || rb.error || ra.text === '' || rb.text === '') {
          verdicts.push({ task: task.id, a: pa.id, b: pb.id, winner: 'error' })
          continue
        }
        process.stdout.write('  judge ' + pa.id + ' vs ' + pb.id + ' on ' + task.id + ' ... ')
        const user = 'Задача: ' + task.prompt + NL + NL
          + 'Ответ A (' + pa.id + '):\n' + ra.text.slice(0, 2000) + NL + NL
          + 'Ответ B (' + pb.id + '):\n' + rb.text.slice(0, 2000)
        const raw = await chat(judge, JUDGE_SYSTEM, user, 0)
        const v = parseJson(raw) || {}
        const winner = v.winner === 'a' ? pa.id : v.winner === 'b' ? pb.id : 'tie'
        verdicts.push({ task: task.id, a: pa.id, b: pb.id, winner: winner, reason: String(v.reason || raw.slice(0, 120)) })
        console.log(winner)
      }
    }
  }

  // 3) scores
  const score = {}
  for (const p of presets) score[p.id] = { win: 0, tie: 0, loss: 0 }
  for (const v of verdicts) {
    if (v.winner === 'error' || v.winner === 'tie') {
      if (v.winner === 'tie') { score[v.a].tie += 1; score[v.b].tie += 1 }
      continue
    }
    score[v.winner].win += 1
    const loser = v.winner === v.a ? v.b : v.a
    score[loser].loss += 1
  }

  const report = { judge, tasks: tasks.map(function (t) { return t.id }), presets: presets.map(function (p) { return p.id }), responses, verdicts, score }
  if (a.out) { writeFileSync(a.out, JSON.stringify(report, null, 2)); console.log('report written to ' + a.out) }

  console.log('')
  console.log('=== A/B summary ===')
  for (const p of presets) {
    const s = score[p.id]
    console.log(p.id.padEnd(10) + ' win=' + s.win + ' tie=' + s.tie + ' loss=' + s.loss)
  }
  console.log('=== verdicts ===')
  for (const v of verdicts) console.log('  ' + v.task + ': ' + v.winner + (v.reason ? ' — ' + String(v.reason).slice(0, 140) : ''))
}

main().catch(function (e) { console.error('ab-bench: ' + e); process.exit(1) })
