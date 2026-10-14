#!/usr/bin/env node
/**
 * dsh-herdr plugin functional test.
 *
 * The plugin is plumbing: dsh lifecycle events -> `herdr pane report-agent`
 * calls against the pane the server injected. What the assertions pin is that
 * plumbing's steady-state contract — the argv Herdr receives, the state
 * mapping, the main-session filter, deduplication, the blocked/back-to-work
 * handshake, and that everything is inert outside a Herdr pane or when the
 * kill switch is set.
 */
import { apply, blockedMessage, herdrTarget, inject, name } from './lib/index.js'

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
  HERDR_BIN_PATH: '/nix/store/herdr-0.9.1/bin/herdr',
}

/** Fake ctx that records spawns and lets the test drive the event bus. */
function harness({ env = { ...BASE_ENV }, graceMs = 0 } = {}) {
  const spawns = []
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
        spawns.push(spec)
        return { done: Promise.resolve({ exitCode: 0, signal: null }) }
      },
    },
  }
  apply(ctx, { env, graceMs, cwd: '/tmp/wt-x' })
  return {
    spawns,
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

// ── state mapping ────────────────────────────────────────────────────────────

const h = harness()
h.emit('session/event', { id: 's1' }, { type: 'turn/start' })
ok(h.spawns.length === 1, 'turn/start reports once')
ok(args(h.spawns[0]).includes('pane report-agent w1:p1'), 'the report addresses the pane')
ok(args(h.spawns[0]).includes('--source dsh-herdr'), 'the report carries the stable source')
ok(args(h.spawns[0]).includes('--agent dsh'), 'the report carries the agent label')
ok(args(h.spawns[0]).includes('--state working'), 'turn/start maps to working')
ok(args(h.spawns[0]).includes('--seq '), 'the report carries a sequence number')
ok(h.spawns[0].cwd === '/tmp/wt-x', 'the report runs in the session cwd')

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
