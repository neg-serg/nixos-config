#!/usr/bin/env node
/**
 * ab-run: autoresearch runtime — run ab-bench on the repo bench set and
 * accumulate versioned reports + a summary CSV.
 *
 * Usage: node ab-run.mjs [--tasks FILE] [--presets FILE] [--judge MODEL]
 *                        [--dir DIR]
 * Defaults: .agent/bench/{tasks,presets}.json; reports in
 * $AB_BENCH_DIR or ~/.local/share/ab-bench/report-<stamp>.json + summary.csv.
 */

import { spawnSync } from 'node:child_process'
import { mkdirSync, readFileSync, writeFileSync, appendFileSync, existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const HERE = dirname(fileURLToPath(import.meta.url))
const DEFAULT_TASKS = join(HERE, '..', 'bench', 'tasks.json')
const DEFAULT_PRESETS = join(HERE, '..', 'bench', 'presets.json')
const OUT_DIR = process.env.AB_BENCH_DIR || join(process.env.HOME, '.local/share', 'ab-bench')

function parseArgs(argv) {
  const out = {}
  for (let i = 0; i < argv.length; i += 2) {
    const key = argv[i]
    if (!key || !key.startsWith('--')) { i -= 1; continue }
    out[key.slice(2)] = argv[i + 1]
  }
  return out
}

function stamp() {
  const d = new Date()
  const p = function (n) { return String(n).padStart(2, '0') }
  return d.getFullYear() + p(d.getMonth() + 1) + p(d.getDate()) + '-' + p(d.getHours()) + p(d.getMinutes()) + p(d.getSeconds())
}

function main() {
  const a = parseArgs(process.argv.slice(2))
  const tasks = a.tasks || DEFAULT_TASKS
  const presets = a.presets || DEFAULT_PRESETS
  const judge = a.judge || 'qwen3:8b-q8_0'
  const dir = a.dir || OUT_DIR
  mkdirSync(dir, { recursive: true })
  const ts = stamp()
  const out = join(dir, 'report-' + ts + '.json')
  const bench = join(HERE, 'ab-bench.mjs')
  if (!existsSync(tasks) || !existsSync(presets)) {
    console.error('ab-run: missing ' + tasks + ' or ' + presets); process.exit(1)
  }
  const res = spawnSync(process.execPath, [bench, '--tasks', tasks, '--presets', presets, '--judge', judge, '--out', out], { stdio: 'inherit' })
  if (res.status !== 0) {
    console.error('ab-run: ab-bench exited with status ' + res.status)
    process.exit(res.status || 1)
  }
  const report = JSON.parse(readFileSync(out, 'utf8'))
  const summaryPath = join(dir, 'summary.csv')
  const header = 'timestamp,task_count,presets,win,tie,loss'
  if (!existsSync(summaryPath)) appendFileSync(summaryPath, header + '\n')
  const presetIds = report.presets.join('|')
  const totals = {}
  for (const pid of report.presets) totals[pid] = { win: 0, tie: 0, loss: 0 }
  for (const v of report.verdicts) {
    if (v.winner === 'error' || v.winner === 'tie') {
      if (v.winner === 'tie') { totals[v.a].tie += 1; totals[v.b].tie += 1 }
      continue
    }
    totals[v.winner].win += 1
    const loser = v.winner === v.a ? v.b : v.a
    totals[loser].loss += 1
  }
  for (const pid of report.presets) {
    const t = totals[pid]
    appendFileSync(summaryPath, ts + ',' + report.tasks.length + ',' + presetIds + ',' + t.win + ',' + t.tie + ',' + t.loss + '\n')
  }
  console.log('')
  console.log('ab-run: report ' + out)
  console.log('ab-run: summary appended to ' + summaryPath)
}

main()
