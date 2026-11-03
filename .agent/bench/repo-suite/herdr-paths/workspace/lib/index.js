/**
 * dsh-herdr: report the dsh agent's lifecycle state to the Herdr runtime.
 *
 * Herdr (https://herdr.dev, package `herdr`) tracks the coding agent in every
 * pane and rolls working/idle/blocked up into its sidebar, notifications and
 * `herdr agent wait`. dsh is not one of the agents Herdr recognizes by reading
 * the screen, but Herdr has a first-class protocol for an agent to report
 * itself: `herdr pane report-agent <pane> --source … --agent … --state …`
 * (https://herdr.dev/docs/add-herdr-support/). Herdr exports HERDR_ENV=1,
 * HERDR_PANE_ID and HERDR_BIN_PATH into every pane, so the plugin drives the
 * same server as the pane it runs in — and stays completely inert outside one.
 *
 * State mapping: `agent/status` running -> working, idle -> idle; the two
 * request waterfalls (`approval/request`, `user-questions/request`) report
 * blocked after a grace period, because the TUI keeps its own promise pending
 * while the card is on screen (the same seam dsh-notify-input uses) and
 * resolving it means the human answered, so the turn goes back to working.
 *
 * Herdr >= 0.9.2 can resume the conversation after a server restart when the
 * agent reports the command that reopens it (see
 * https://herdr.dev/docs/add-herdr-support/): every state report then carries
 * `dsh --profile tui --resume <id>` after `--`. Older servers reject that
 * trailing argv, so the plugin probes `herdr --version` once and attaches the
 * command only when it is supported.
 *
 * Reports are fire-and-forget: a missing binary, a stopped server or a slow
 * socket must never disturb the session. Only the main session drives the pane
 * state — subagent sessions run, finish and question inside the same pane.
 */

/** Cordis plugin name — must match the patch row / package name. */
export const name = 'dsh-herdr'

/** Required service: the subprocess seam. Listening on the event bus needs none. */
export const inject = ['subprocess']

/** Report source; must stay stable and must not start with `herdr:`. */
const SOURCE = 'dsh-herdr'

/** The name Herdr shows in the sidebar, agent list and notifications. */
const AGENT = 'dsh'

/** How long a request stays pending before the pane is marked blocked (ms). */
const DEFAULT_GRACE_MS = 3_000

const MAX_MESSAGE_CHARS = 200
const COLLECT_BYTES = 1024

/**
 * The Herdr pane this process runs in, or null outside one.
 * @param env - process environment (HERDR_* are set by the Herdr server).
 */
export function herdrTarget(env) {
  if (env.HERDR_ENV !== '1') return null
  const pane = env.HERDR_PANE_ID
  const bin = env.HERDR_BIN_PATH
  if (pane === undefined || pane === '' || bin === undefined || bin === '') return null
  return { pane, bin }
}

/** Kill switch, matching the repo's other dsh plugins. */
function disabled(env) {
  const flag = env.DSH_HERDR
  return flag === '0' || flag === 'false' || env.VITEST === '1' || env.VITEST === 'true'
}

/**
 * Parse `herdr X.Y.Z` output; null when it carries no version.
 * @param text - `herdr --version` stdout
 */
export function parseHerdrVersion(text) {
  const match = /(\d+)\.(\d+)\.(\d+)/.exec(String(text ?? ''))
  if (match === null) return null
  return [Number(match[1]), Number(match[2]), Number(match[3])]
}

/** Lexicographic [major, minor, patch] comparison. */
function atLeast(version, want) {
  for (let index = 0; index < want.length; index += 1) {
    if (version[index] !== want[index]) return version[index] > want[index]
  }
  return true
}

/** Control characters would let a message inject its own arguments. */
function sanitize(text, limit = MAX_MESSAGE_CHARS) {
  return String(text ?? '')
    .replace(/[\u0000-\u001f\u007f]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, limit)
}

/**
 * Blocked-state message for the two request waterfalls.
 * @param event - `approval/request` or `user-questions/request`.
 * @param payload - the request payload the TUI is showing.
 */
export function blockedMessage(event, payload) {
  if (event === 'approval/request') {
    const tool = sanitize(payload?.toolName, 60)
    if (tool === '') return 'approval needed'
    const reason = sanitize(payload?.reason, 120)
    return reason === '' ? tool : tool + ' — ' + reason
  }
  const first = payload?.questions?.[0]
  const question = sanitize(first?.question ?? first?.header, MAX_MESSAGE_CHARS)
  return question === '' ? 'question for the user' : question
}

/**
 * Mount the reporter.
 * @param ctx - plugin context; the event bus and `ctx.subprocess` are the only seams used.
 * @param config - optional `graceMs`, `env` (tests), `cwd` (tests).
 */
export function apply(ctx, config) {
  const settings = config ?? {}
  const graceMs = Number.isFinite(settings.graceMs) ? settings.graceMs : DEFAULT_GRACE_MS
  const env = settings.env ?? process.env
  const target = herdrTarget(env)
  if (target === null) return

  const state = { seq: Date.now(), last: null, sessionId: null, resume: false }
  const timers = new Set()

  /**
   * Attach the resume command only when the pane's Herdr accepts it: 0.9.2 is
   * where `pane report-agent -- <argv>` appeared, and older servers reject the
   * trailing argv outright, so the report would be lost.
   */
  function probeResumeSupport() {
    if (disabled(env)) return
    void (async () => {
      try {
        const handle = ctx.subprocess.spawn({
          argv: [target.bin, '--version'],
          cwd: settings.cwd ?? process.cwd(),
          stdio: {
            stdin: 'ignore',
            stdout: { maxBytes: COLLECT_BYTES },
            stderr: { maxBytes: COLLECT_BYTES },
          },
          graceMs: 1000,
        })
        await handle.done
        const parsed = parseHerdrVersion(handle.collected?.stdout?.readFrom(0)?.text ?? '')
        if (parsed !== null) state.resume = atLeast(parsed, [0, 9, 2])
      } catch {
        /* no version read -> keep reporting state without a resume command */
      }
    })()
  }

  function report(next, message) {
    if (disabled(env)) return
    if (next === state.last) return
    state.last = next
    state.seq += 1
    const argv = [
      target.bin,
      'pane',
      'report-agent',
      target.pane,
      '--source',
      SOURCE,
      '--agent',
      AGENT,
      '--state',
      next,
      '--seq',
      String(state.seq),
    ]
    if (message !== undefined && message !== '') argv.push('--message', message)
    if (state.sessionId !== null) argv.push('--agent-session-id', state.sessionId)
    if (state.resume && state.sessionId !== null) {
      // What Herdr runs when a server restart restores this pane.
      argv.push('--', 'dsh', '--profile', 'tui', '--resume', state.sessionId)
    }
    void (async () => {
      try {
        const handle = ctx.subprocess.spawn({
          argv,
          cwd: settings.cwd ?? process.cwd(),
          stdio: {
            stdin: 'ignore',
            stdout: { maxBytes: COLLECT_BYTES },
            stderr: { maxBytes: COLLECT_BYTES },
          },
          graceMs: 1000,
        })
        await handle.done
      } catch {
        /* a report must never disturb the session */
      }
    })()
  }

  /** The first session observed is the interactive one; subagents come later. */
  function mainSession(session) {
    if (session === undefined || session === null || session.id === undefined) return false
    if (state.sessionId === null) state.sessionId = String(session.id)
    return String(session.id) === state.sessionId
  }

  ctx.on('session/event', (session, event) => {
    if (event === undefined || !mainSession(session)) return
    if (event.type === 'turn/start') report('working')
  })

  ctx.on('agent/status', (payloadEvent) => {
    const status = payloadEvent?.status
    if (!mainSession(payloadEvent?.agent?.session)) return
    if (status === 'running') report('working')
    else if (status === 'idle') report('idle')
  })

  function watchRequest(event) {
    ctx.on(
      event,
      (payload, next) => {
        let timer = null
        const disarm = () => {
          if (timer === null) return
          clearTimeout(timer)
          timers.delete(timer)
          timer = null
        }

        if (!disabled(env)) {
          timer = setTimeout(() => {
            timers.delete(timer)
            timer = null
            report('blocked', blockedMessage(event, payload))
          }, graceMs)
          timers.add(timer)
        }

        if (typeof next !== 'function') return undefined
        let result
        try {
          result = next()
        } catch (error) {
          disarm()
          throw error
        }
        if (timer !== null) {
          const settled = () => {
            disarm()
            if (state.last === 'blocked') report('working')
          }
          Promise.resolve(result).then(settled, settled)
        }
        return result
      },
      // Only the main session's questions/approvals block the pane: subagent
      // requests would otherwise flip the pane state while the main agent keeps
      // working. `prepend`/`global` match dsh-notify-input — the TUI's own
      // handler never calls `next()` on the interactive branch.
      { prepend: true, global: true },
    )
  }

  watchRequest('approval/request')
  watchRequest('user-questions/request')

  probeResumeSupport()

  ctx.effect(() => () => {
    for (const timer of timers) clearTimeout(timer)
    timers.clear()
  }, name + ': shutdown')
}
