#!/usr/bin/env node
/**
 * harness-bench: measure the harness, not the model's trivia.
 *
 * Runs one headless `dsh` per case x trial in a throwaway workspace, harvests
 * the NDJSON event stream (`--json`), and records the metrics that actually
 * cost time and money: pass (a check command's exit code), steps, wall clock,
 * input/output/cache/reasoning tokens, tool calls and tool errors per tool.
 * The usage numbers come from the `step_end` status events, which already fold
 * retries; a step whose usage is incomplete is reported, not guessed.
 *
 * Modes:
 *   run     --suite FILE [--out FILE] [--trials N] [--profile P] [--keep] [--allow-failures]
 *   verify  --suite FILE        prove each case is red before the fix and green after it
 *   compare A.json B.json
 *
 * Suite format (JSON; relative paths resolve against the suite file):
 *   {
 *     "name": "smoke",
 *     "profile": "headless",
 *     "trials": 1,
 *     "timeoutMs": 300000,
 *     "pricing": { "inputUsdPerMTokens": 0.27, "cacheReadUsdPerMTokens": 0.07,
 *                  "cacheWriteUsdPerMTokens": 0.27, "outputUsdPerMTokens": 1.10 },
 *     "cases": [
 *       { "id": "x", "prompt": "...", "workspace": "./fixtures/x",
 *         "gold": "./fixes/x", "frozen": ["test.mjs"],
 *         "setup": "optional command", "check": "node check.mjs" }
 *   }
 *
 * A case passes when `check` exits 0. No `check` means no pass/fail signal, so
 * such a case is refused: a benchmark without a success criterion is a demo.
 * `gold` is the known-good tree for `verify` only; `frozen` files are hashed
 * before and after the run so a case cannot be won by editing its own test.
 * Metrics are paired by case in `compare`, so per-case variance cancels; the
 * shows steps/turn with sd ~= mean (66 +/- 66), which makes unpaired "it felt
 * better" comparisons noise.
 */
import { spawn } from 'node:child_process'
import { createHash } from 'node:crypto'
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'

const USAGE_KEYS = {
  inputTokens: 'input',
  outputTokens: 'output',
  cacheReadTokens: 'cacheRead',
  cacheWriteTokens: 'cacheWrite',
  reasoningTokens: 'reasoning',
  totalTokens: 'total',
}

function parseArgv(argv) {
  const flags = {}
  const positional = []
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (!arg.startsWith('--')) { positional.push(arg); continue }
    const name = arg.slice(2)
    const next = argv[i + 1]
    if (next === undefined || next.startsWith('--')) { flags[name] = true } else { flags[name] = next; i += 1 }
  }
  return { flags, positional }
}

function readJson(path, label) {
  try { return JSON.parse(readFileSync(path, 'utf8')) } catch (e) {
    throw new Error(label + ': cannot read ' + path + ': ' + e.message)
  }
}

function emptyUsage() {
  return { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, reasoning: 0, total: 0 }
}

function addUsage(into, usage) {
  for (const [key, name] of Object.entries(USAGE_KEYS)) {
    const value = Number(usage[key])
    if (Number.isFinite(value)) into[name] += value
  }
  return into
}

/** Fold one trial's NDJSON lines plus its wall clock and check result. */
function summarize(ndjson, meta) {
  const usage = emptyUsage()
  const toolCalls = {}
  let steps = 0
  let turns = 0
  let calls = 0
  let toolErrors = 0
  let incompleteSteps = 0
  let finalChars = 0
  let sessionId = null
  let usageEvents = 0
  for (const line of ndjson.split('\n')) {
    if (line.trim() === '') continue
    let event
    try { event = JSON.parse(line) } catch { continue }
    if (event.type === 'session') { sessionId = event.sessionId ?? null; continue }
    if (event.type === 'final') { finalChars = String(event.text ?? '').length; continue }
    if (event.type === 'tool_call') { calls += 1; toolCalls[event.tool] = (toolCalls[event.tool] ?? 0) + 1; continue }
    if (event.type === 'tool_result') { if (event.status === 'error') toolErrors += 1; continue }
    if (event.type !== 'status') continue
    if (event.phase === 'turn_start') { turns += 1; continue }
    if (event.phase === 'step_start') { steps += 1; continue }
    if (event.phase !== 'step_end') continue
    if (event.usage === undefined) { incompleteSteps += 1; continue }
    usageEvents += 1
    addUsage(usage, event.usage)
  }
  return {
    ...meta,
    sessionId,
    steps,
    turns,
    calls,
    toolCalls,
    toolErrors,
    incompleteSteps,
    usage,
    usageEvents,
    finalChars,
  }
}

function costOf(usage, pricing) {
  if (!pricing) return null
  const perM = (tokens, usd) => (Number(tokens) * Number(usd ?? 0)) / 1e6
  return perM(usage.input, pricing.inputUsdPerMTokens)
    + perM(usage.cacheRead, pricing.cacheReadUsdPerMTokens)
    + perM(usage.cacheWrite, pricing.cacheWriteUsdPerMTokens)
    + perM(usage.output, pricing.outputUsdPerMTokens)
}

/** Spawn a process, capture both streams, kill its group after `timeoutMs`. */
function exec(command, args, opts) {
  return new Promise((complete) => {
    const startedAt = Date.now()
    // `detached` puts the child in its own process group so a timeout can kill
    // tool subprocesses too: a killed parent alone leaves grandchildren holding
    // the stdout pipes open, and `close` then never fires.
    const child = spawn(command, args, { cwd: opts.cwd, env: opts.env ?? process.env, stdio: ['ignore', 'pipe', 'pipe'], detached: true })
    let stdout = ''
    let stderr = ''
    let timedOut = false
    let settled = false
    const finish = (code, signal) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      clearTimeout(force)
      complete({ code, signal, stdout, stderr, timedOut, wallMs: Date.now() - startedAt })
    }
    const timer = setTimeout(() => {
      timedOut = true
      try { process.kill(-child.pid, 'SIGKILL') } catch { child.kill('SIGKILL') }
    }, opts.timeoutMs)
    // Last-resort unblock if a stream still refuses to close after the kill.
    const force = setTimeout(() => finish(null, null), opts.timeoutMs + 5000)
    child.stdout.on('data', (chunk) => { stdout += chunk })
    child.stderr.on('data', (chunk) => { stderr += chunk })
    child.on('error', (error) => {
      stderr += '\n' + error.message
      finish(null, null)
    })
    child.on('close', (code, signal) => finish(code, signal))
  })
}

function tail(text, lines) {
  return text.trim().split('\n').slice(-lines).join('\n')
}

function frozenHashes(workspace, testCase) {
  const hashes = {}
  for (const relative of testCase.frozen ?? []) {
    const path = join(workspace, relative)
    hashes[relative] = existsSync(path) ? createHash('sha256').update(readFileSync(path)).digest('hex') : 'missing'
  }
  return hashes
}

/** Overlay the case's known-good tree (its `gold` directory) on a workspace. */
function applyGold(workspace, suitePath, testCase) {
  if (!testCase.gold) throw new Error('case ' + testCase.id + ' has no gold overlay')
  cpSync(resolve(dirname(suitePath), testCase.gold), workspace, { recursive: true })
}

async function runTrial(suite, suitePath, testCase, trial, opts) {
  const workspace = mkdtempSync(join(tmpdir(), 'dsh-bench-'))
  const timeoutMs = Number(testCase.timeoutMs ?? suite.timeoutMs ?? 300000)
  try {
    if (testCase.workspace) {
      cpSync(resolve(dirname(suitePath), testCase.workspace), workspace, { recursive: true })
    }
    if (testCase.setup) {
      const setup = await exec('bash', ['-lc', testCase.setup], { cwd: workspace, timeoutMs })
      if (setup.code !== 0) throw new Error('setup failed for ' + testCase.id + ': ' + tail(setup.stderr || setup.stdout, 5))
    }
    const before = frozenHashes(workspace, testCase)
    const bin = opts.bin
    const profile = testCase.profile ?? opts.profile ?? suite.profile ?? 'headless'
    const run = await exec(bin, ['--profile', profile, 'headless', '--json', testCase.prompt], { cwd: workspace, timeoutMs })
    let check = { code: null, output: '', skipped: false }
    if (testCase.check) {
      const checked = await exec('bash', ['-lc', testCase.check], { cwd: workspace, timeoutMs: Math.min(timeoutMs, 120000) })
      check = { code: checked.code, output: tail(checked.stdout + '\n' + checked.stderr, 8), skipped: false, timedOut: checked.timedOut }
    } else {
      check = { code: null, output: '', skipped: true }
    }
    const after = frozenHashes(workspace, testCase)
    const frozenChanged = Object.keys(before).filter((relative) => before[relative] !== after[relative])
    const result = summarize(run.stdout, {
      case: testCase.id,
      trial,
      exitCode: run.code,
      timedOut: run.timedOut,
      wallMs: run.wallMs,
      pass: check.skipped ? null : check.code === 0 && frozenChanged.length === 0,
      frozenChanged,
      checkOutput: check.output,
      stderrTail: tail(run.stderr, 5),
    })
    result.costUsd = costOf(result.usage, suite.pricing)
    if (run.stdout.trim() === '') throw new Error('no NDJSON on stdout for ' + testCase.id + ': ' + tail(run.stderr, 8))
    if (!opts.keep) rmSync(workspace, { recursive: true, force: true })
    else result.workspace = workspace
    return result
  } catch (error) {
    if (!opts.keep) rmSync(workspace, { recursive: true, force: true })
    return {
      case: testCase.id,
      trial,
      pass: false,
      error: String(error && error.message ? error.message : error),
      wallMs: 0,
      steps: 0,
      turns: 0,
      calls: 0,
      toolCalls: {},
      toolErrors: 0,
      incompleteSteps: 0,
      usage: emptyUsage(),
      usageEvents: 0,
      finalChars: 0,
      costUsd: null,
    }
  }
}

function mean(values) {
  const finite = values.filter((value) => Number.isFinite(value))
  return finite.length === 0 ? null : finite.reduce((sum, value) => sum + value, 0) / finite.length
}

function aggregate(trials) {
  const byCase = new Map()
  for (const trial of trials) {
    if (!byCase.has(trial.case)) byCase.set(trial.case, [])
    byCase.get(trial.case).push(trial)
  }
  const cases = []
  for (const [id, rows] of byCase) {
    const scored = rows.filter((row) => row.pass !== null)
    cases.push({
      case: id,
      trials: rows.length,
      passRate: scored.length === 0 ? null : scored.filter((row) => row.pass).length / scored.length,
      steps: mean(rows.map((row) => row.steps)),
      wallMs: mean(rows.map((row) => row.wallMs)),
      tokens: mean(rows.map((row) => row.usage.total)),
      input: mean(rows.map((row) => row.usage.input)),
      output: mean(rows.map((row) => row.usage.output)),
      cacheRead: mean(rows.map((row) => row.usage.cacheRead)),
      costUsd: mean(rows.map((row) => row.costUsd)),
      calls: mean(rows.map((row) => row.calls)),
      toolErrors: mean(rows.map((row) => row.toolErrors)),
    })
  }
  cases.sort((a, b) => a.case.localeCompare(b.case))
  const totals = {
    trials: trials.length,
    passRate: mean(cases.map((row) => row.passRate)),
    wallMs: mean(cases.map((row) => row.wallMs)),
    tokens: mean(cases.map((row) => row.tokens)),
    costUsd: mean(cases.map((row) => row.costUsd)),
  }
  return { cases, totals }
}

/** Two-sided exact sign test over discordant pairs (wins vs losses). */
function signTest(wins, losses) {
  const n = wins + losses
  if (n === 0) return 1
  const k = Math.min(wins, losses)
  let tail = 0
  for (let i = 0; i <= k; i += 1) tail += choose(n, i)
  return Math.min(1, (2 * tail) / 2 ** n)
}

function choose(n, k) {
  let value = 1
  for (let i = 1; i <= k; i += 1) value = (value * (n - k + i)) / i
  return value
}

/** Percentile bootstrap over per-case deltas; deterministic enough for a report. */
function bootstrapCi(deltas, resamples = 5000) {
  const finite = deltas.filter((value) => Number.isFinite(value))
  if (finite.length < 2) return null
  const means = []
  for (let i = 0; i < resamples; i += 1) {
    let sum = 0
    for (let j = 0; j < finite.length; j += 1) sum += finite[Math.floor(Math.random() * finite.length)]
    means.push(sum / finite.length)
  }
  means.sort((a, b) => a - b)
  return { low: means[Math.floor(resamples * 0.025)], high: means[Math.floor(resamples * 0.975)] }
}

function fmt(value, digits = 1) {
  if (value === null || value === undefined) return '-'
  if (typeof value === 'number') return Number.isInteger(value) ? String(value) : value.toFixed(digits)
  return String(value)
}

function printReport(run) {
  console.log('\n' + run.suite + '  profile=' + run.profile + '  runs=' + run.trials.length)
  console.log('case                     pass   steps    wall_s    tokens   cache%   calls  errors   $')
  for (const row of aggregate(run.trials).cases) {
    const cachePct = row.tokens ? (row.cacheRead / (row.tokens)) * 100 : null
    console.log(
      row.case.padEnd(24)
      + (' ' + fmt(row.passRate === null ? null : row.passRate * 100, 0) + '%').padStart(6)
      + fmt(row.steps).padStart(7)
      + fmt(row.wallMs === null ? null : row.wallMs / 1000).padStart(9)
      + fmt(row.tokens).padStart(10)
      + fmt(cachePct).padStart(8)
      + fmt(row.calls).padStart(7)
      + fmt(row.toolErrors).padStart(8)
      + (row.costUsd === null ? '       -' : (' ' + row.costUsd.toFixed(4)).padStart(8)),
    )
  }
}

/**
* Prove a suite can discriminate: every case must fail its check on the
* untouched workspace and pass it once the `gold` overlay is applied. A case
* that is green before the fix measures nothing, and a case that stays red
* after it has a broken check or a stale gold tree.
*/
async function modeVerify(flags, positional) {
  if (!flags.suite || typeof flags.suite !== 'string') throw new Error('verify needs --suite FILE')
  const suitePath = resolve(flags.suite)
  const suite = readJson(suitePath, 'suite')
  const cases = (suite.cases ?? []).filter((testCase) => testCase.workspace)
  if (cases.length === 0) throw new Error('verify needs cases with a workspace and a gold overlay')
  let failures = 0
  console.log('\ncase                       red    green  verdict')
  for (const testCase of cases) {
    const workspace = mkdtempSync(join(tmpdir(), 'dsh-verify-'))
    const timeoutMs = Number(testCase.timeoutMs ?? suite.timeoutMs ?? 300000)
    try {
      cpSync(resolve(dirname(suitePath), testCase.workspace), workspace, { recursive: true })
      if (testCase.setup) {
        const setup = await exec('bash', ['-lc', testCase.setup], { cwd: workspace, timeoutMs: Math.min(timeoutMs, 120000) })
        if (setup.code !== 0) throw new Error('setup failed for ' + testCase.id + ': ' + tail(setup.stderr || setup.stdout, 5))
      }
      const red = await exec('bash', ['-lc', testCase.check], { cwd: workspace, timeoutMs: Math.min(timeoutMs, 120000) })
      applyGold(workspace, suitePath, testCase)
      const green = await exec('bash', ['-lc', testCase.check], { cwd: workspace, timeoutMs: Math.min(timeoutMs, 120000) })
      const ok = red.code !== 0 && green.code === 0
      if (!ok) failures += 1
      console.log(
        testCase.id.padEnd(26)
        + (red.code !== 0 ? 'fail' : 'PASS').padStart(6)
        + (green.code === 0 ? ' pass' : ' FAIL').padStart(10)
        + ('  ' + (ok ? 'ok' : 'not discriminating'))
      )
      if (!ok) {
        console.log('  red:   ' + tail(red.stdout + '\n' + red.stderr, 3))
        console.log('  green: ' + tail(green.stdout + '\n' + green.stderr, 3))
      }
    } finally {
      rmSync(workspace, { recursive: true, force: true })
    }
  }
  console.log('\n' + (cases.length - failures) + '/' + cases.length + ' cases discriminate')
  if (failures > 0) process.exitCode = 1
}

async function modeRun(flags, positional) {
  if (!flags.suite || typeof flags.suite !== 'string') throw new Error('run needs --suite FILE')
  const suitePath = resolve(flags.suite)
  const suite = readJson(suitePath, 'suite')
  if (!Array.isArray(suite.cases) || suite.cases.length === 0) throw new Error('suite has no cases')
  const missing = suite.cases.filter((testCase) => !testCase.check)
  if (missing.length > 0) throw new Error('cases without a check are refused: ' + missing.map((testCase) => testCase.id).join(', '))
  const trials = Number(flags.trials ?? suite.trials ?? 1)
  const concurrency = Math.max(1, Number(flags.concurrency ?? 1))
  const bin = process.env.DSH_BIN || flags.bin || 'dsh'
  const out = resolve(flags.out || join(process.cwd(), 'harness-run-' + Date.now() + '.json'))
  const startedAt = new Date().toISOString()
  const queue = []
  for (const testCase of suite.cases) for (let trial = 1; trial <= trials; trial += 1) queue.push({ testCase, trial })
  console.log('harness-bench: ' + suite.name + ' — ' + suite.cases.length + ' cases x ' + trials + ' trials, bin=' + bin)
  const results = []
  let index = 0
  async function worker() {
    while (index < queue.length) {
      const item = queue[index]
      index += 1
      process.stderr.write('  [' + index + '/' + queue.length + '] ' + item.testCase.id + ' #' + item.trial + '\r')
      results.push(await runTrial(suite, suitePath, item.testCase, item.trial, { bin, profile: flags.profile, keep: flags.keep === true }))
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, queue.length) }, worker))
  process.stderr.write('\n')
  const run = {
    suite: suite.name,
    profile: suite.profile ?? 'headless',
    startedAt,
    finishedAt: new Date().toISOString(),
    pricing: suite.pricing ?? null,
    trials: results.sort((a, b) => (a.case + a.trial).localeCompare(b.case + b.trial)),
  }
  mkdirSync(dirname(out), { recursive: true })
  writeFileSync(out, JSON.stringify(run, null, 2) + '\n')
  printReport(run)
  const scored = results.filter((row) => row.pass !== null)
  if (scored.length > 0) {
    console.log('\noverall pass: ' + scored.filter((row) => row.pass).length + '/' + scored.length
      + (run.pricing ? '   cost: $' + (aggregate(results).totals.costUsd ?? 0).toFixed(4) : ''))
  }
  console.log('run written to ' + out)
  if (scored.some((row) => !row.pass) && flags['allow-failures'] !== true) process.exitCode = 1
}

function modeReport(flags, positional) {
  const path = positional[0]
  if (!path) throw new Error('report needs RUN.json')
  printReport(readJson(resolve(path), 'run'))
}

function modeCompare(positional) {
  const [aPath, bPath] = positional
  if (!aPath || !bPath) throw new Error('compare needs A.json B.json')
  const a = readJson(resolve(aPath), 'run A')
  const b = readJson(resolve(bPath), 'run B')
  const aCases = new Map(aggregate(a.trials).cases.map((row) => [row.case, row]))
  const bCases = new Map(aggregate(b.trials).cases.map((row) => [row.case, row]))
  const shared = [...aCases.keys()].filter((id) => bCases.has(id)).sort()
  if (shared.length === 0) throw new Error('the two runs share no case ids')
  console.log('\nA = ' + aPath + '\nB = ' + bPath + '\n')
  console.log('case                     pass A    pass B   d_pass   d_steps  d_tokens   d_wall_s      d_$')
  const metric = { pass: [], steps: [], tokens: [], wall: [], cost: [] }
  let wins = 0
  let losses = 0
  for (const id of shared) {
    const left = aCases.get(id)
    const right = bCases.get(id)
    const dPass = right.passRate === null || left.passRate === null ? null : right.passRate - left.passRate
    const dSteps = right.steps - left.steps
    const dTokens = right.tokens - left.tokens
    const dWall = (right.wallMs - left.wallMs) / 1000
    const dCost = right.costUsd === null || left.costUsd === null ? null : right.costUsd - left.costUsd
    if (dPass !== null && dPass !== 0) { if (dPass > 0) wins += 1; else losses += 1 }
    for (const [key, value] of Object.entries({ pass: dPass, steps: dSteps, tokens: dTokens, wall: dWall, cost: dCost })) {
      if (value !== null && Number.isFinite(value)) metric[key].push(value)
    }
    console.log(
      id.padEnd(24)
      + fmt(left.passRate === null ? null : left.passRate * 100, 0).padStart(7)
      + fmt(right.passRate === null ? null : right.passRate * 100, 0).padStart(9)
      + fmt(dPass === null ? null : dPass * 100, 0).padStart(9)
      + fmt(dSteps, 1).padStart(9)
      + fmt(dTokens, 0).padStart(10)
      + fmt(dWall, 1).padStart(11)
      + (dCost === null ? '         -' : dCost.toFixed(4).padStart(10)),
    )
  }
  const meanOf = (values) => (values.length === 0 ? null : values.reduce((sum, value) => sum + value, 0) / values.length)
  console.log('\nmean deltas (B - A): pass ' + fmt(meanOf(metric.pass) === null ? null : meanOf(metric.pass) * 100, 1) + ' pt'
    + '   steps ' + fmt(meanOf(metric.steps), 1)
    + '   tokens ' + fmt(meanOf(metric.tokens), 0)
    + '   wall ' + fmt(meanOf(metric.wall), 1) + ' s')
  const tokensCi = bootstrapCi(metric.tokens)
  if (tokensCi) console.log('tokens delta 95% bootstrap CI: [' + fmt(tokensCi.low, 0) + ', ' + fmt(tokensCi.high, 0) + ']')
  console.log('sign test on pass: ' + wins + ' win / ' + losses + ' loss, p = ' + fmt(signTest(wins, losses), 3))
  console.log('paired cases: ' + shared.length + (shared.length < 6 ? ' — fewer than ~6 discordant pairs cannot reach p<0.05' : ''))
}

async function main() {
  const { flags, positional } = parseArgv(process.argv.slice(2))
  const mode = positional.shift()
  if (mode === 'run') return modeRun(flags, positional)
  if (mode === 'verify') return modeVerify(flags, positional)
  if (mode === 'report') return modeReport(flags, positional)
  if (mode === 'compare') return modeCompare(positional)
  throw new Error('usage: harness-bench.mjs run --suite FILE | verify --suite FILE | report RUN.json | compare A.json B.json')
}

main().catch((error) => {
  console.error('harness-bench: ' + (error && error.message ? error.message : error))
  process.exit(2)
})
