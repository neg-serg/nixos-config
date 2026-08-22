/**
 * dsh-category-skill-reminder: after several direct work-tool calls without
 * delegation, nudge the model to delegate via subagent and load the matching
 * skill through the real `skill` tool.
 *
 * Middle-path design: the nudge fires ONLY when the current task text
 * actually overlaps with a skill in the catalog (name or description tokens),
 * and it is delivered as a <system-reminder> block — the same convention the
 * workspace-instruction plugin uses, so the model treats it as instructions
 * rather than a soft advisory user line. No hard gate: steps are never
 * blocked. After a delegation the streak re-arms, so a later long direct
 * stretch can get a fresh nudge.
 */

import { createUserMessage } from '@deepseek-ai/dsh-llm'

export const name = 'dsh-category-skill-reminder'

const WORK = new Set(['read', 'write', 'edit', 'str_replace_editor', 'bash', 'rg', 'glob'])
const DELEGATE = new Set(['subagent', 'subagent_fork'])
const DEFAULT_THRESHOLD = 3

const REMINDER_OPEN = '<system-reminder>'
const REMINDER_CLOSE = '</system-reminder>'

/** Per-agent nudging state (WeakMap: object lifetime bounds entries). */
const state = new WeakMap()

/** Text of the most recent user message (role user/user-message), if any. */
function lastUserText(messages) {
  const list = Array.isArray(messages) ? messages : []
  for (let i = list.length - 1; i >= 0; i -= 1) {
    const m = list[i]
    const role = m?.role ?? m?.type ?? ''
    if (role !== 'user' && role !== 'user-message') continue
    const text = m?.content
    if (typeof text === 'string' && text.trim() !== '') return text
    if (Array.isArray(text)) {
      const joined = text.map((b) => (b && typeof b.text === 'string' ? b.text : '')).join(' ').trim()
      if (joined !== '') return joined
    }
  }
  return ''
}

/** Significant lowercase tokens of a text (words with more than 3 chars). */
function tokens(text) {
  const seen = new Set()
  const words = String(text || '').toLowerCase().match(/[a-zа-яё0-9_]{4,}/gi) || []
  for (const w of words) seen.add(w)
  return seen
}

/**
 * Pick the skill whose name or description overlaps the task text, or null.
 * Name hit is decisive; description needs at least two shared significant tokens.
 */
function matchSkill(skills, taskText) {
  const task = tokens(taskText)
  if (task.size === 0) return null
  let best = null
  let bestScore = 0
  for (const s of skills) {
    const nameTokens = tokens(s.name)
    let nameHit = false
    for (const t of nameTokens) {
      if (task.has(t)) { nameHit = true; break }
    }
    if (nameHit) return s
    const descTokens = tokens(s.description)
    let shared = 0
    for (const t of descTokens) {
      if (task.has(t)) shared += 1
    }
    if (shared > bestScore) { bestScore = shared; best = s }
  }
  return bestScore >= 2 ? best : null
}

export function apply(ctx, config) {
  const threshold = (config && config.threshold) || DEFAULT_THRESHOLD

  ctx.on('tools/post-execute', async (exec, _result, next) => {
    const downstream = await next()
    const agent = exec.agent
    if (!agent) return downstream

    let s = state.get(agent)
    if (!s) {
      s = { work: 0, pending: false, shown: false }
      state.set(agent, s)
    }

    if (DELEGATE.has(exec.name)) {
      // A delegation resets the streak and re-arms the nudge for later.
      s.work = 0
      s.pending = false
      s.shown = false
      return downstream
    }
    if (WORK.has(exec.name)) s.work += 1
    if (s.work >= threshold && !s.pending && !s.shown) {
      s.pending = true
    }
    return downstream
  })

  ctx.on('agent/pre-step', async ({ agent, messages, signal }, next) => {
    const decision = await next()
    if (decision.kind === 'reject') return decision

    const s = state.get(agent)
    if (!s || !s.pending) return decision

    // Conditional firing: only nudge when the task text actually overlaps a
    // catalog skill. No overlap (or no skills) → stay silent.
    let skills = []
    try {
      if (ctx.skills && typeof ctx.skills.snapshot === 'function') {
        const snapshot = await ctx.skills.snapshot({
          cwd: agent.session.header.cwd,
          signal,
          scope: agent,
        })
        skills = (snapshot.skills || []).map(function (x) {
          return { name: x.name || '', description: x.description || '' }
        })
      }
    } catch (e) { skills = [] }
    const taskText = lastUserText(decision.messages || messages)
    const matched = matchSkill(skills, taskText)
    if (matched === null) return decision

    s.pending = false
    s.shown = true

    const text =
      REMINDER_OPEN +
      ' Текущая задача похожа на скилл «' + matched.name + '». ' +
      'ОБЯЗАТЕЛЬНО: если задача действительно покрывается этим скиллом — сначала вызови инструмент `skill` с именем «' + matched.name + '», ' +
      'потом работай. Если работа повторяющаяся или широкая и не покрывается скиллом — делегируй через `subagent` ' +
      '(см. .agent/workflows/delegate-task.md: TASK/EXPECTED OUTCOME/MUST DO/MUST NOT DO/CONTEXT).' +
      ' ' + REMINDER_CLOSE

    return {
      ...decision,
      messages: [
        ...decision.messages,
        createUserMessage({
          content: [{ type: 'text', text }],
          source: { kind: 'plugin', plugin: 'category-skill-reminder' },
        }),
      ],
    }
  })
}
