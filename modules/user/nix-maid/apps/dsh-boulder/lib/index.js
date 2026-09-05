/**
 * dsh-boulder: todo-continuation enforcer (the "boulder").
 *
 * Wakes an idle agent that still has incomplete todos and steers it to
 * continue (proceed without permission, mark done, do not stop). Ported from
 * oh-my-opencode todo-continuation-enforcer; design in
 * /etc/nixos/docs/howto/designs/boulder.md. Advisory drive: never edits todos
 * itself, only injects a system directive via agent.steer().
 *
 * v1 scope: host-side logic only (no countdown toast client). Backoff base
 * follows the omo reference implementation (CONTINUATION_COOLDOWN_MS = 5s,
 * x2 per failure up to x32, cap 5 consecutive failures then 5 min pause) —
 * note the backlog doc mentions 30s base; kept 5s to match upstream code.
 */

import { createUserMessage } from '@deepseek-ai/dsh-llm'

export const name = 'dsh-boulder'

const COUNTDOWN_SECONDS = 2
const COUNTDOWN_GRACE_PERIOD_MS = 500
const ABORT_WINDOW_MS = 3000
const CONTINUATION_COOLDOWN_MS = 5000
const MAX_CONSECUTIVE_FAILURES = 5
const FAILURE_RESET_WINDOW_MS = 5 * 60 * 1000
const MAX_STAGNATION_COUNT = 3
const COMPACTION_GUARD_MS = 60 * 1000
const DEFAULT_SKIP_AGENTS = []

const CONTINUATION_PROMPT =
  '[system-directive todo_continuation]\n' +
  'Incomplete tasks remain in your todo list. Continue working on the next pending task.\n' +
  '- Proceed without asking for permission\n' +
  '- Mark each task complete when finished\n' +
  '- Do not stop until all tasks are done\n' +
  '- If you believe all work is already complete, the system is questioning your completion claim. ' +
  'Critically re-examine each todo item from a skeptical perspective, verify the work was actually ' +
  'done correctly, and update the todo list accordingly.'

function readTodos(agent, ctx) {
  try {
    if (ctx.sessionProjections && ctx.sessionProjections.snapshot) {
      const snap = ctx.sessionProjections.snapshot(agent.session).values.todos
      if (Array.isArray(snap)) return snap
    }
  } catch (e) { /* fall through to event fold */ }
  const events = Array.from((agent.session && agent.session.events) || [])
  for (let i = events.length - 1; i >= 0; i--) {
    if (events[i].type === 'todo/write') return events[i].data.todos || []
  }
  return []
}

function incompleteCount(todos) {
  return todos.filter(function (t) { return t.status !== 'completed' }).length
}

function createSessionState() {
  return {
    countdownTimer: undefined,
    countdownStartedAt: undefined,
    lastInjectedAt: undefined,
    lastIncompleteCount: undefined,
    stagnationCount: 0,
    consecutiveFailures: 0,
    inFlight: false,
    wasCancelled: false,
    abortDetectedAt: undefined,
    allTodosCompletedAt: undefined,
    recentCompactionAt: undefined,
  }
}

export function apply(ctx, config) {
  const skipAgents = (config && config.skipAgents) || DEFAULT_SKIP_AGENTS
  const store = new Map() // sessionID -> state

  function getState(sid) {
    let s = store.get(sid)
    if (!s) { s = createSessionState(); store.set(sid, s) }
    return s
  }

  function cancelCountdown(sid) {
    const s = store.get(sid)
    if (s && s.countdownTimer) {
      clearTimeout(s.countdownTimer)
      s.countdownTimer = undefined
    }
  }

  function pushToast(sid, message) {
    // Best-effort server->client push; no-op when the connection service is not
    // exposed here (the browser half also renders via window.__boulderToast).
    try {
      if (ctx.client && typeof ctx.client.emit === 'function') {
        ctx.client.emit('boulder-toast', { sessionID: sid, message })
      }
    } catch (e) { /* ignore bridge failures */ }
  }

  function startCountdown(agent, incomplete, total) {
    const sid = agent.session.id
    const s = getState(sid)
    s.countdownStartedAt = Date.now()
    const remaining = total - incomplete
    pushToast(sid, 'Resuming in ' + COUNTDOWN_SECONDS + 's... (' + remaining + ' tasks remaining)')
    s.countdownTimer = setTimeout(function () {
      s.countdownTimer = undefined
      void injectContinuation(agent, incomplete, total)
    }, COUNTDOWN_SECONDS * 1000)
  }

  async function injectContinuation(agent, initialIncomplete, initialTotal) {
    const sid = agent.session.id
    const s = getState(sid)
    if (s.inFlight) return
    if (Date.now() - s.countdownStartedAt < COUNTDOWN_GRACE_PERIOD_MS) return
    s.inFlight = true
    try {
      const todos = readTodos(agent, ctx)
      const incomplete = incompleteCount(todos)
      if (incomplete === 0) {
        s.allTodosCompletedAt = Date.now()
        return
      }
      const total = todos.length
      const done = total - incomplete
      const list = todos
        .filter(function (t) { return t.status !== 'completed' })
        .map(function (t) { return '- [' + t.status + '] ' + t.content })
        .join('\n')
      const prompt = CONTINUATION_PROMPT + '\n' +
        '[Status: ' + done + '/' + total + ' completed, ' + incomplete + ' remaining]\n' + list
      agent.steer(createUserMessage({
        content: [{ type: 'text', text: prompt }],
        source: { kind: 'user' },
      }))
      s.consecutiveFailures = 0
      s.lastInjectedAt = Date.now()
      s.stagnationCount = 0
    } catch (err) {
      s.consecutiveFailures += 1
      s.lastInjectedAt = Date.now()
      s.wasCancelled = /cancell/i.test(String(err))
    } finally {
      s.inFlight = false
    }
  }

  async function handleIdle(agent) {
    const sid = agent.session.id
    const s = getState(sid)
    const now = Date.now()

    if (s.allTodosCompletedAt || s.wasCancelled || s.inFlight) return
    if (s.abortDetectedAt && now - s.abortDetectedAt < ABORT_WINDOW_MS) {
      s.abortDetectedAt = undefined
      return
    }

    const todos = readTodos(agent, ctx)
    const incomplete = incompleteCount(todos)
    if (incomplete === 0) {
      s.allTodosCompletedAt = now
      return
    }

    if (s.recentCompactionAt && now - s.recentCompactionAt < COMPACTION_GUARD_MS) return

    const agentName = agent.name || ''
    if (skipAgents.indexOf(agentName) !== -1) return

    if (s.consecutiveFailures >= MAX_CONSECUTIVE_FAILURES) {
      if (s.lastInjectedAt && now - s.lastInjectedAt >= FAILURE_RESET_WINDOW_MS) {
        s.consecutiveFailures = 0
      } else {
        return
      }
    }

    const cooldown = CONTINUATION_COOLDOWN_MS * Math.pow(2, Math.min(s.consecutiveFailures, 5))
    if (s.lastInjectedAt && now - s.lastInjectedAt < cooldown) return

    const prev = s.lastIncompleteCount
    if (prev !== undefined) {
      if (incomplete < prev) s.stagnationCount = 0
      else if (incomplete === prev) s.stagnationCount += 1
    }
    s.lastIncompleteCount = incomplete
    if (s.stagnationCount >= MAX_STAGNATION_COUNT) return

    startCountdown(agent, incomplete, todos.length)
  }

  ctx.on('agent/status', function (payload) {
    const agent = payload && payload.agent
    const status = payload && payload.status
    if (!agent || !agent.session) return
    const sid = agent.session.id
    if (status === 'running') {
      cancelCountdown(sid)
      return
    }
    if (status !== 'idle') return
    void handleIdle(agent)
  })

  ctx.on('agent/pre-step', function (payload, next) {
    const agent = payload && payload.agent
    if (agent && agent.session) cancelCountdown(agent.session.id)
    // agent/pre-step is a waterfall: every listener must call next() and
    // return its result, or the whole pre-step chain resolves to undefined
    // and downstream listeners crash on decision.kind (reading 'kind').
    return next()
  })

  ctx.on('session/event', function (session, event) {
    if (!session) return
    const sid = session.id
    if (event.type === 'compaction/start' || event.type === 'compaction/end') {
      getState(sid).recentCompactionAt = Date.now()
    } else if (event.type === 'session/end-seed') {
      const s = store.get(sid)
      if (s && s.countdownTimer) clearTimeout(s.countdownTimer)
      store.delete(sid)
    }
  })

  ctx.effect(function () {
    return function () {
      store.forEach(function (s) {
        if (s.countdownTimer) clearTimeout(s.countdownTimer)
      })
      store.clear()
    }
  }, name + ': shutdown')
}
