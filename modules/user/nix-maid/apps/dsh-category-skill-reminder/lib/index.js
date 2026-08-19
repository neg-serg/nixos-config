/**
 * dsh-category-skill-reminder: after several direct work-tool calls without
 * delegation, nudge the model to delegate via subagent and pass the right
 * skills through load_skills.
 *
 * Ported from oh-my-opencode category-skill-reminder idea (see
 * /etc/nixos/docs/howto/designs/rules-hooks.md section 3). Delivery: one
 * synthetic user message injected before the next step (agent/pre-step),
 * same mechanism as dsh-tool-skill. Advisory only.
 */

import { createUserMessage } from '@deepseek-ai/dsh-llm'

export const name = 'dsh-category-skill-reminder'

const WORK = new Set(['read', 'write', 'edit', 'str_replace_editor', 'bash', 'rg', 'glob'])
const DELEGATE = new Set(['subagent', 'subagent_fork'])
const DEFAULT_THRESHOLD = 3

/** Per-agent nudging state (WeakMap: object lifetime bounds entries). */
const state = new WeakMap()

export function apply(ctx, config) {
  const threshold = (config && config.threshold) || DEFAULT_THRESHOLD

  ctx.on('tools/post-execute', async (exec, _result, next) => {
    const downstream = await next()
    const agent = exec.agent
    if (!agent) return downstream

    let s = state.get(agent)
    if (!s) {
      s = { delegated: false, work: 0, pending: false, shown: false }
      state.set(agent, s)
    }

    if (DELEGATE.has(exec.name)) {
      s.delegated = true
      s.pending = false
      return downstream
    }
    if (WORK.has(exec.name)) s.work += 1
    if (s.work >= threshold && !s.delegated && !s.pending && !s.shown) {
      s.pending = true
    }
    return downstream
  })

  ctx.on('agent/pre-step', async ({ agent, signal }, next) => {
    const decision = await next()
    if (decision.kind === 'reject') return decision

    const s = state.get(agent)
    if (!s || !s.pending) return decision
    s.pending = false
    s.shown = true

    let skillsText = ''
    try {
      if (ctx.skills && typeof ctx.skills.snapshot === 'function') {
        const snapshot = await ctx.skills.snapshot({
          cwd: agent.session.header.cwd,
          signal,
          scope: agent,
        })
        const skills = snapshot.skills || []
        const names = skills.map(function (x) { return x.name })
        if (names.length > 0) {
          skillsText = 'Доступные скиллы: ' + names.join(', ') + '. Передавай нужные через load_skills при делегировании.'
        }
      }
    } catch (e) { /* skills unavailable — omit the catalog line */ }

    const text =
      '[Category+Skill Reminder] Ты делаешь много прямых правок без делегирования. ' +
      'Если работа повторяющаяся или широкая — делегируй через `subagent` (см. ' +
      '.agent/workflows/delegate-task.md: TASK/EXPECTED OUTCOME/MUST DO/MUST NOT DO/CONTEXT).' +
      (skillsText ? ' ' + skillsText : '')

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
