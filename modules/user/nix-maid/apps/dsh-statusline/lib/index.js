/**
 * dsh-statusline: a session status line in the terminal's title.
 *
 * Upstream Tianshu ships a scriptable status line (`StatusLineRunner`, the
 * Claude-Code-compatible protocol: session JSON on stdin, first stdout line
 * rendered above the input). In rc.29 that class is exported but never
 * instantiated, so the feature cannot be switched on from configuration — the
 * render slot above the input belongs to the TUI.
 *
 * What a plugin *can* own is the terminal title: the TUI never writes OSC 0/1/2,
 * so this plugin drives kitty/Ghostty/WezTerm/the tab bar with the same status
 * text. That text comes from the `dsh-statusline` script (packages/local-bin),
 * which speaks the documented protocol — so if the upstream runner is ever
 * wired, the same script plugs in unchanged.
 *
 * Steady-state contract copied from upstream's runner, because the reasons are
 * the same: throttle (default 3s), single flight (skip while the previous run is
 * outstanding), keep the previous title when the script fails or is too slow,
 * never let the title flicker with an empty string.
 *
 * The frame is the better surface, so the two never render at once: the patch
 * that wires the runner into the frame publishes `globalThis.__dshTuiStatusLineFrame`,
 * and this plugin stands down while that marker is present (set
 * DSH_STATUSLINE_TARGET=title|both to override, e.g. to keep the title in sync
 * as well).
 */

/** Cordis plugin name — must match the patch row / package name. */
export const name = 'dsh-statusline'

/** Required service: the subprocess seam. Listening on the event bus needs none. */
export const inject = ['subprocess']

const DEFAULT_COMMAND = 'dsh-statusline'
const DEFAULT_INTERVAL_MS = 3_000
const MAX_TITLE_CHARS = 300
const MAX_OUTPUT_BYTES = 8 * 1024

/** Kill switch, matching the notify conventions already in this repo. */
function disabled(env) {
  const flag = env.DSH_STATUSLINE
  return flag === '0' || flag === 'false'
}

function flagOn(env, key) {
  return env[key] === '1' || env[key] === 'true'
}

/** Control characters would let the title smuggle escape sequences. */
function sanitize(text) {
  return String(text)
    .replace(/[\u0000-\u001f\u007f]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, MAX_TITLE_CHARS)
}

/** OSC 2 = window title, OSC 1 = icon name (the tab title in kitty). */
export function titleSequence(title) {
  return `\u001b]2;${title}\u0007\u001b]1;${title}\u0007`
}

export function apply(ctx, config) {
  const settings = config ?? {}
  const intervalMs = Number.isFinite(settings.intervalMs) ? settings.intervalMs : DEFAULT_INTERVAL_MS
  const state = { lastRunMs: 0, inFlight: false, current: null, inputTokens: new Map(), turn: new Map() }

  function command() {
    return settings.command ?? process.env.DSH_STATUSLINE_CMD ?? DEFAULT_COMMAND
  }

  function payload(session) {
    const id = session?.id ?? 'unknown'
    const estimated = state.inputTokens.get(id)
    const body = {
      session_id: id,
      turn: state.turn.get(id) ?? -1,
      workspace: { current_dir: session?.header?.cwd ?? process.cwd() },
    }
    if (typeof estimated === 'number' && Number.isFinite(estimated)) {
      body.context = { estimated_tokens: estimated }
    }
    return body
  }

  /** The frame renderer (dsh-tui-ru patch) publishes this marker; see module doc. */
  function frameOwnsStatusLine() {
    if (globalThis.__dshTuiStatusLineFrame !== true) return false
    const target = process.env.DSH_STATUSLINE_TARGET
    return target !== 'title' && target !== 'both'
  }

  async function refresh(session) {
    if (disabled(process.env) || flagOn(process.env, 'VITEST')) return
    if (frameOwnsStatusLine()) return
    if (process.stdout === undefined || process.stdout.isTTY !== true) return
    const sid = session?.id ?? 'unknown'
    const now = Date.now()
    if (state.inFlight || now - state.lastRunMs < intervalMs) return
    state.lastRunMs = now

    let bin = command()
    if (typeof ctx.subprocess.resolveExecutable === 'function') {
      try {
        bin = await ctx.subprocess.resolveExecutable(bin)
      } catch {
        return // the helper is not installed — the feature is optional, stay silent
      }
    }

    state.inFlight = true
    try {
      const handle = ctx.subprocess.spawn({
        argv: [bin],
        cwd: session?.header?.cwd ?? process.cwd(),
        stdio: {
          stdin: { data: JSON.stringify(payload(session)) },
          stdout: { maxBytes: MAX_OUTPUT_BYTES },
          stderr: 'ignore',
        },
        graceMs: 1000,
      })
      const outcome = await handle.done
      if (outcome.exitCode !== 0) return
      const first = (handle.collected.stdout?.readFrom(0)?.text ?? '').split('\n')[0] ?? ''
      const title = sanitize(first)
      if (title === '' || title === state.current) return
      state.current = title
      process.stdout.write(titleSequence(title))
    } catch {
      /* a failed status line must never disturb the session */
    } finally {
      state.inFlight = false
      void sid
    }
  }

  ctx.on('session/event', (session, event) => {
    if (session === undefined || event === undefined) return
    if (event.type === 'assistant/message') {
      const usage = event.data?.usage
      const input = usage?.inputTokens
      const cached = usage?.cacheReadTokens
      if (typeof input === 'number') {
        state.inputTokens.set(
          session.id,
          input + (typeof cached === 'number' ? cached : 0)
        )
      }
      if (typeof event.data?.turn === 'number') state.turn.set(session.id, event.data.turn)
      return
    }
    if (event.type === 'turn/end') {
      if (typeof event.data?.turn === 'number') state.turn.set(session.id, event.data.turn)
      void refresh(session)
    }
  })

  ctx.on('agent/status', (payloadEvent) => {
    const agent = payloadEvent?.agent
    if (agent?.session === undefined || payloadEvent?.status !== 'idle') return
    void refresh(agent.session)
  })

  ctx.effect(() => () => {
    state.inputTokens.clear()
    state.turn.clear()
  }, name + ': shutdown')
}
