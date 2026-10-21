#!/usr/bin/env node
/**
 * dsh-herdr plugin functional test.
 *
 * The plugin is plumbing: dsh lifecycle events -> `herdr pane report-agent`
 * calls against the pane the server injected, plus `herdr pane
 * report-metadata` for the turn/token/session row. What the assertions pin is
 * that plumbing's steady-state contract — the argv Herdr receives, the state
 * mapping, the main-session filter, deduplication, the blocked/back-to-work
 * handshake, the metadata throttle, dedupe and TTL, and that everything is inert
 * outside a Herdr pane or when the kill switch is set.
 */
import { apply, blockedMessage, formatTokens, herdrTarget, inject, name, parseHerdrVersion } from './lib/index.js'

let pass = 0
let fail = 0
const ok = (cond, label) => {
  if (cond) {
    pass += 1
    console.log('  ✅ ' + label)
  } else {
    fail += 1
    console.log('  ❌ ' + label)
  }
}

const BASE_ENV = {
  HERDR_ENV: '1',
  HERDR_PANE_ID: 'w1:p1',
  HERDR_BIN_PATH: '/nix/store/herdr-0.9.3/bin/herdr',
}

/** Fake ctx that records spawns and lets the test drive the event bus. */
function harness({
  env = { ...BASE_ENV },
  graceMs = 0,
  version = 'herdr 0.9.3\n',
  metadataIntervalMs = 0,
} = {}) {
  const spawns = []
  const probes = []
  const metadata = []
  const listeners = {}
  const cleanups = []
  const ctx = {
    on: (event, fn, opts) => {
      ;(listeners[event] ??= []).push({ fn, opts })
    },
    effect: (fn) => {
      cleanups.push(fn)
    },
    subprocess: {
      spawn: (spec) => {
        // The version probe is not a report: keep it out of `spawns` so the
        // report assertions below count state reports only.
        if (spec.argv.includes('--version')) {
          probes.push(spec)
          return {
            done: Promise.resolve({ exitCode: 0, signal: null }),
            collected: { stdout: { readFrom: () => ({ text: version }) } },
          }
        }
        // Display metadata is chrome next to the lifecycle report: keep the two
        // apart so the state assertions below count reports only.
        if (spec.argv.includes('report-metadata')) {
          metadata.push(spec)
          return {
            done: Promise.resolve({ exitCode: 0, signal: null }),
            collected: { stdout: { readFrom: () => ({ text: '' }) } },
          }
        }
        spawns.push(spec)
        return {
          done: Promise.resolve({ exitCode: 0, signal: null }),
          collected: { stdout: { readFrom: () => ({ text: '' }) } },
        }
      },
    },
  }
  apply(ctx, { env, graceMs, metadataIntervalMs, cwd: '/tmp/wt-x' })
  return {
    spawns,
    probes,
    metadata,
    listeners,
    cleanups,
    emit: (event, ...args) => {
      for (const entry of listeners[event] ?? []) entry.fn(...args)
    },
  }
}

const tick = () => new Promise((resolve) => setTimeout(resolve, 0))
const args = (spawn) => spawn.argv.join(' ')

// ── environment gates ────────────────────────────────────────────────────────

ok(name === 'dsh-herdr', 'the plugin name matches the patch row')
ok(inject.includes('subprocess'), 'the plugin injects the subprocess seam')
ok(herdrTarget({}) === null, 'no HERDR_ENV -> no target')
ok(herdrTarget({ ...BASE_ENV, HERDR_ENV: '0' }) === null, 'HERDR_ENV=0 -> no target')
ok(herdrTarget(BASE_ENV)?.pane === 'w1:p1', 'HERDR_ENV=1 -> the pane id is the target')

const inert = harness({ env: {} })
ok(Object.keys(inert.listeners).length === 0, 'outside Herdr the plugin registers nothing')
ok(inert.spawns.length === 0, 'outside Herdr the plugin never spawns')
ok(inert.probes.length === 0, 'outside Herdr the plugin never probes for a version')

// ── resume-command support ───────────────────────────────────────────────────

ok(JSON.stringify(parseHerdrVersion('herdr 0.9.3\n')) === '[0,9,3]', 'the version probe parses herdr output')
ok(parseHerdrVersion('nonsense') === null, 'unparseable version output -> null')

// ── state mapping ────────────────────────────────────────────────────────────

const h = harness()
await tick()
ok(h.probes.length === 1, 'inside Herdr the plugin probes the binary version once')
ok(args(h.probes[0]).endsWith('herdr --version'), 'the probe asks the pane binary for its version')
h.emit('session/event', { id: 's1' }, { type: 'turn/start' })
ok(h.spawns.length === 1, 'turn/start reports once')
ok(args(h.spawns[0]).includes('pane report-agent w1:p1'), 'the report addresses the pane')
ok(args(h.spawns[0]).includes('--source dsh-herdr'), 'the report carries the stable source')
ok(args(h.spawns[0]).includes('--agent dsh'), 'the report carries the agent label')
ok(args(h.spawns[0]).includes('--state working'), 'turn/start maps to working')
ok(args(h.spawns[0]).includes('--seq '), 'the report carries a sequence number')
ok(h.spawns[0].cwd === '/tmp/wt-x', 'the report runs in the session cwd')
ok(
  args(h.spawns[0]).includes('-- dsh --profile tui --resume s1'),
  'a 0.9.2+ server gets the resume command with the first report',
)

h.emit('agent/status', { agent: { session: { id: 's1' } }, status: 'idle' })
ok(h.spawns.length === 2, 'idle reports once')
ok(args(h.spawns[1]).includes('--state idle'), 'agent/status idle maps to idle')

h.emit('agent/status', { agent: { session: { id: 's1' } }, status: 'idle' })
ok(h.spawns.length === 2, 'a repeated state is deduplicated')

h.emit('agent/status', { agent: { session: { id: 's1' } }, status: 'running' })
ok(args(h.spawns[2]).includes('--state working'), 'agent/status running maps to working')

ok(args(h.spawns[2]).includes('--agent-session-id s1'), 'the main session id rides along')

h.emit('agent/status', { agent: { session: { id: 'sub-1' } }, status: 'idle' })
ok(h.spawns.length === 3, 'subagent status never drives the pane state')

// ── display metadata ─────────────────────────────────────────────────────────

ok(formatTokens(842) === '842', 'small token counts stay exact')
ok(formatTokens(619_123) === '619k', 'token counts are compacted like the status line')
ok(formatTokens(1_800) === '2k', 'token counts round to whole thousands')
ok(formatTokens(null) === null, 'a missing count formats to null')

const meta = harness()
meta.emit('session/event', { id: 's9' }, { type: 'turn/start' })
meta.emit('session/event', { id: 's9' }, {
  type: 'assistant/message',
  data: { turn: 4, usage: { inputTokens: 1180, cacheReadTokens: 20 } },
})
ok(meta.metadata.length === 1, 'an assistant message reports metadata once')
ok(
  args(meta.metadata[0]).includes('pane report-metadata w1:p1'),
  'metadata addresses the pane',
)
ok(args(meta.metadata[0]).includes('--source dsh-herdr'), 'metadata carries the same source')
ok(args(meta.metadata[0]).includes('--token turn=4'), 'the turn rides along')
ok(args(meta.metadata[0]).includes('--token tokens=1k'), 'input plus cached tokens are summed')
ok(args(meta.metadata[0]).includes('--token session=s9'), 'the session id is exposed, shortened')
ok(args(meta.metadata[0]).includes('--ttl-ms '), 'metadata expires')

meta.emit('session/event', { id: 's9' }, {
  type: 'assistant/message',
  data: { turn: 4, usage: { inputTokens: 1180, cacheReadTokens: 20 } },
})
ok(meta.metadata.length === 1, 'identical metadata is deduplicated')

meta.emit('session/event', { id: 's9' }, { type: 'turn/end', data: { turn: 5 } })
ok(meta.metadata.length === 2, 'a turn boundary flushes metadata')
ok(args(meta.metadata[1]).includes('--token turn=5'), 'the flushed metadata carries the new turn')

meta.emit('session/event', { id: 'sub-2' }, {
  type: 'assistant/message',
  data: { turn: 9, usage: { inputTokens: 9000 } },
})
ok(meta.metadata.length === 2, 'subagent usage never reaches the pane metadata')

const throttled = harness({ metadataIntervalMs: 60_000 })
throttled.emit('session/event', { id: 's10' }, { type: 'turn/start' })
throttled.emit('session/event', { id: 's10' }, {
  type: 'assistant/message',
  data: { turn: 1, usage: { inputTokens: 1000 } },
})
throttled.emit('session/event', { id: 's10' }, {
  type: 'assistant/message',
  data: { turn: 1, usage: { inputTokens: 2000 } },
})
ok(throttled.metadata.length === 1, 'streaming usage is throttled to one report per interval')

const metaOff = harness({ env: {} })
metaOff.emit('session/event', { id: 's11' }, {
  type: 'assistant/message',
  data: { turn: 1, usage: { inputTokens: 1000 } },
})
ok(metaOff.metadata.length === 0, 'outside Herdr metadata is never reported')

// ── resume stays off on older servers ────────────────────────────────────────

const old = harness({ version: 'herdr 0.9.1\n' })
await tick()
old.emit('session/event', { id: 's3' }, { type: 'turn/start' })
ok(old.spawns.length === 1, 'an old server still gets the state report')
ok(args(old.spawns[0]).includes('--agent-session-id s3'), 'an old server still gets the session id')
ok(!args(old.spawns[0]).includes('-- dsh'), 'an old server gets no resume command')

// ── blocked handshake ────────────────────────────────────────────────────────

const blocked = harness()
let release
const pending = new Promise((resolve) => {
  release = resolve
})
blocked.emit('approval/request', { toolName: 'bash', reason: 'writes outside the workspace' }, () => pending)
await tick()
ok(blocked.spawns.length === 1, 'a pending approval reports after the grace')
ok(args(blocked.spawns[0]).includes('--state blocked'), 'a pending approval maps to blocked')
ok(args(blocked.spawns[0]).includes('--message bash'), 'the approval names the tool')
release()
await tick()
await tick()
ok(blocked.spawns.length === 2, 'answering the card reports again')
ok(args(blocked.spawns[1]).includes('--state working'), 'an answered card returns the pane to working')

const instant = harness({ graceMs: 5000 })
instant.emit('user-questions/request', { questions: [{ question: 'Which branch?' }] }, () => Promise.resolve())
await tick()
ok(instant.spawns.length === 0, 'an auto-settled request stays silent')

const kill = harness({ env: { ...BASE_ENV, DSH_HERDR: '0' } })
kill.emit('session/event', { id: 's2' }, { type: 'turn/start' })
ok(kill.spawns.length === 0, 'DSH_HERDR=0 disables every report')
ok(kill.probes.length === 0, 'DSH_HERDR=0 skips the version probe too')

ok(blockedMessage('approval/request', { toolName: 'write' }) === 'write', 'approval copy falls back to the tool name')
ok(
  blockedMessage('user-questions/request', { questions: [{ question: 'Which branch?' }] }) === 'Which branch?',
  'question copy uses the first question',
)

const cleanup = harness().cleanups
ok(cleanup.length === 1, 'the plugin registers a shutdown effect')
cleanup[0]()
ok(true, 'the shutdown effect runs without timers')

console.log(`\ndsh-herdr: ${pass} passed, ${fail} failed`)
process.exit(fail === 0 ? 0 : 1)
