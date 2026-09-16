/**
 * dsh-notify-input: tell the human when the agent stops and waits for them.
 *
 * The TUI notifies on work that *finished* — a subagent, a workflow, a
 * background task (the three `notifyOs` call sites in the bundle). Nothing fires
 * for the two requests that **block the turn**: the approval card and the
 * structured question. Both are host request events the TUI owns as waterfall
 * listeners, and its approval handler resolves its own promise while the card is
 * on screen — so a listener registered after it never runs. This plugin
 * registers with `prepend: true`, continues the waterfall with `next()`, and
 * reports a request only once it has stayed unresolved for `graceMs`: an
 * auto-approved tool (always-approve mode, a session grant, an allowed prefix)
 * settles on the next microtask and stays silent, while a card waiting on a
 * human keeps the timer alive.
 *
 * The notification is an OSC sequence on stdout — control-only, so it never
 * touches the visible grid and interleaving it with the renderer is safe. The
 * protocol table mirrors the bundle's own `notify-osc` patch: kitty OSC 99,
 * iTerm2/WezTerm/Ghostty OSC 9. An unrecognised terminal stays silent rather
 * than shelling out to `notify-send` (see docs/howto/dsh-notify-input.md).
 */

import { readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

/** Cordis plugin name — must match the patch row / package name. */
export const name = 'dsh-notify-input'

/** No hard dependency: the host event bus is the only seam this plugin uses. */
export const inject = []

/** Default delay before a still-pending request is reported (ms). */
export const DEFAULT_GRACE_MS = 3_000

/** Control characters would let a payload inject its own escape sequence. */
export function sanitize(text, limit) {
  return String(text ?? '')
    .replace(/[\u0000-\u001f\u007f]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, limit)
}

/** OSC protocol for this terminal, or null when it cannot be identified. */
export function detectProtocol(env) {
  const forced = env.DSH_NOTIFY_OSC
  if (forced === '0' || forced === 'false') return null
  if (forced === '1' || forced === 'true') return 'osc9'
  if (env.KITTY_WINDOW_ID !== undefined && env.KITTY_WINDOW_ID !== '') return 'kitty'
  const term = String(env.TERM ?? '')
  if (term.includes('kitty')) return 'kitty'
  if (/^(iTerm\.app|WezTerm|ghostty)$/i.test(String(env.TERM_PROGRAM ?? ''))) return 'osc9'
  if (term.includes('ghostty')) return 'osc9'
  return null
}

/**
 * kitty takes OSC 99 (ST-terminated); the OSC 9 family ends with BEL.
 * @returns the escape sequence, or null when there is no text to send.
 */
export function notifySequence(protocol, title, body) {
  const head = sanitize(title, 80)
  const rest = sanitize(body, 200)
  const text = head === '' ? rest : rest === '' ? head : head + ' — ' + rest
  if (text === '') return null
  if (protocol === 'kitty') return '\u001b]99;;' + text + '\u001b\\'
  return '\u001b]9;' + text + '\u0007'
}

/**
 * `/config notify off` writes `prefs.notifyOs = false` — the same switch the
 * bundle's own notifications honour, so honouring it here keeps one knob.
 * @returns false only for an explicit false; unreadable prefs default to on.
 */
export function parseNotifyPref(text) {
  try {
    const parsed = JSON.parse(text)
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) return true
    return parsed.notifyOs !== false
  } catch {
    return true
  }
}

/** Environment kill switches, matching the bundle's `notify-osc` gates. */
export function envAllows(env) {
  if (env.DSH_NOTIFY_INPUT === '0' || env.DSH_NOTIFY_INPUT === 'false') return false
  if (env.DSH_TUI_SKIP_NOTIFY === '1' || env.DSH_TUI_SKIP_NOTIFY === 'true') return false
  if (env.VITEST === '1' || env.VITEST === 'true') return false
  if (env.CI === '1' || env.CI === 'true') return false
  return true
}

/** Approval request -> notification copy; null when there is nothing to say. */
export function approvalNotice(request) {
  const tool = sanitize(request?.toolName, 60)
  if (tool === '') return null
  const reason = sanitize(request?.reason, 120)
  return {
    title: 'dsh · Нужно подтверждение',
    body: reason === '' ? tool : tool + ' — ' + reason,
  }
}

/** Question request -> notification copy; only the first question is reported. */
export function questionNotice(request) {
  const first = request?.questions?.[0]
  if (first === undefined || first === null) return null
  const question = sanitize(first.question, 160) || sanitize(first.header, 60)
  if (question === '') return null
  return { title: 'dsh · Агент ждёт ответа', body: question }
}

/**
 * Mount the notifier.
 * @param ctx - plugin context; the host event bus is the only seam used.
 * @param config - optional `graceMs`, `stdout` (tests), `prefsPath` (null = off).
 */
export function apply(ctx, config) {
  const settings = config ?? {}
  const graceMs = Number.isFinite(settings.graceMs) ? settings.graceMs : DEFAULT_GRACE_MS
  const stdout = settings.stdout ?? process.stdout
  const prefsPath =
    settings.prefsPath === null
      ? null
      : (settings.prefsPath ?? join(homedir(), '.dsh-tui', 'prefs.json'))

  /** Armed grace timers, cleared when the plugin unloads. */
  const timers = new Set()

  function notificationsEnabled(env) {
    if (!envAllows(env)) return false
    if (prefsPath === null) return true
    try {
      return parseNotifyPref(readFileSync(prefsPath, 'utf8'))
    } catch {
      return true // no prefs file yet — the default is on
    }
  }

  function notify(notice, env) {
    if (notice === null || !notificationsEnabled(env)) return false
    if (stdout === undefined || stdout === null || stdout.isTTY !== true) return false
    const protocol = detectProtocol(env)
    if (protocol === null) return false
    const sequence = notifySequence(protocol, notice.title, notice.body)
    if (sequence === null) return false
    try {
      stdout.write(sequence)
      return true
    } catch {
      return false
    }
  }

  /**
   * Report `notice` only if the request is still unresolved after the grace.
   * `next()` settling is exactly "a human answered" (the TUI keeps its promise
   * pending while the card is up) versus "it was auto-approved".
   */
  function watch(event, describe) {
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
        try {
          if (notificationsEnabled(process.env)) {
            const notice = describe(payload)
            if (notice !== null) {
              timer = setTimeout(() => {
                timers.delete(timer)
                timer = null
                notify(notice, process.env)
              }, graceMs)
              timers.add(timer)
            }
          }
        } catch {
          /* a notification must never break the request path */
        }
        if (typeof next !== 'function') return undefined
        let result
        try {
          result = next()
        } catch (error) {
          disarm()
          throw error
        }
        if (timer !== null) Promise.resolve(result).then(disarm, disarm)
        return result
      },
      // `prepend` puts this listener at the head of the waterfall, ahead of the
      // TUI's own handler — which never calls `next()` on the interactive
      // branch, so an appended listener would never see the case that matters.
      // `global` bypasses the dispatch context filter, which the TUI's question
      // handler also opts out of (`user-questions/request`, `{ global: true }`).
      // Running first means requests the TUI ignores (another session, no card)
      // also arm the timer; they do not block on a human, so they settle and the
      // timer is disarmed before the grace elapses.
      { prepend: true, global: true },
    )
  }

  watch('approval/request', approvalNotice)
  watch('user-questions/request', questionNotice)

  ctx.effect(() => () => {
    for (const timer of timers) clearTimeout(timer)
    timers.clear()
  }, name + ': shutdown')
}
