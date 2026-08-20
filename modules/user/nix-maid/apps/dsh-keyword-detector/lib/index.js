/**
 * dsh-keyword-detector: trigger keywords in the latest user message → hint.
 *
 * Harness hook from oh-my-opencode backlog ("keyword-detector"): cheap,
 * regex-only trigger that watches for user phrases implying a mode change or
 * a specific behaviour (e.g. "не пиши в чат по-китайски", "коротко",
 * "сначала план", "делегируй", "проверь факты"). On a match it injects one
 * short user-role directive on the next agent/pre-step (same mechanism as
 * dsh-ttsr / dsh-json-error-recovery). Config: { rules?: [{pattern, hint}] }
 * — defaults to the built-in table below.
 *
 * Per-session cap (MAX_PER_SESSION) and per-rule cooldown keep it quiet.
 */

import { createUserMessage } from '@deepseek-ai/dsh-llm'

export const name = 'dsh-keyword-detector'
export const inject = []

const MAX_PER_SESSION = 6

const DEFAULT_RULES = [
  { pattern: /(не пиши|не отвечай).*(китай|中文|по-русски|русском)/i, hint: 'Отвечай по-русски; китайский не использовать никогда.' },
  { pattern: /(коротко|кратко|покороче|лаконично)/i, hint: 'Отвечай коротко: 1-3 предложения, без предисловий и повторов.' },
  { pattern: /(сначала план|план перед кодом|сначала подумай)/i, hint: 'Сначала составь план (plan-before-code), потом код — не начинай править вслепую.' },
  { pattern: /(делегируй|субагент|параллельно)/i, hint: 'Делегируй независимые куски субагентам (delegate-task.md) и продолжай свою работу параллельно.' },
  { pattern: /(проверь факты|проверь.*(репо|состояние)|evidence)/i, hint: 'Проверяй факты по репозиторию/документам перед утверждениями (evidence-first).' },
  { pattern: /(переключи|режим|mode)/i, hint: 'Уточни режим работы и следуй ему до явной смены.' },
]

function lastUserText(messages) {
  const list = Array.isArray(messages) ? messages : []
  for (let i = list.length - 1; i >= 0; i -= 1) {
    const m = list[i]
    const role = m?.role ?? m?.type ?? ''
    if (role !== 'user' && role !== 'user-message') continue
    const text = m?.content
    if (typeof text === 'string' && text.trim() !== '') return text
    if (Array.isArray(text)) {
      const t = text.map((b) => (b && typeof b.text === 'string' ? b.text : '')).join(' ').trim()
      if (t !== '') return t
    }
  }
  return ''
}

export function apply(ctx, config) {
  config = config || {}
  const rules = Array.isArray(config.rules) && config.rules.length > 0 ? config.rules : DEFAULT_RULES
  const fired = new Map()
  const lastUser = new Map()
  ctx.on('agent/pre-step', async ({ agent, messages }, next) => {
    const decision = await next()
    if (decision.kind === 'reject') return decision
    const sid = agent && agent.session ? agent.session.id : 'default'
    const userText = lastUserText(messages || decision.messages)
    if (userText === '') return decision
    if (lastUser.get(sid) === userText) return decision // already handled this message
    lastUser.set(sid, userText)
    const count = fired.get(sid) || 0
    if (count >= MAX_PER_SESSION) return decision
    const injections = []
    for (const rule of rules) {
      if (!rule.pattern.test(userText)) continue
      if (fired.get(sid) === count && injections.length > 0) continue // one hint per message
      injections.push(createUserMessage({
        content: [{ type: 'text', text: '[keyword:' + String(rule.pattern) + '] ' + rule.hint }],
        source: { kind: 'plugin', plugin: 'keyword-detector' },
      }))
    }
    if (injections.length === 0) return decision
    fired.set(sid, count + injections.length)
    return { ...decision, messages: [...decision.messages, ...injections] }
  })
}
