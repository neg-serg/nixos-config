/**
 * dsh-agent-usage-reminder: gentle, advisory nudge to use subagents for
 * repetitive manual search/exploration instead of grinding through the same
 * search tools inline.
 *
 * Pattern: @deepseek-ai/dsh-repeat-tool-reminder (tools/post-execute +
 * additionalContexts delivery; never blocks or rewrites calls). Idea ported
 * from oh-my-opencode "agent-usage-reminder" (see
 * /etc/nixos/docs/howto/designs/rules-hooks.md). Mounted via the profile's
 * cordis.patch.yml insert row, same as dsh-osm / dsh-gui-tweaks.
 */

import { createUserMessage } from '@deepseek-ai/dsh-llm'

export const name = 'dsh-agent-usage-reminder'

const DEFAULTS = { maxReminders: 3 }

/** Tool names that count as "manual search/exploration" worth delegating. */
const SEARCH_TOOLS = new Set(['rg', 'glob', 'grep', 'web_search'])

/** Tools that count as "already delegating" — they silence the nudge. */
const AGENT_TOOLS = new Set(['subagent', 'subagent_fork'])

const REMINDER_TEXT =
  'You have done several manual search/exploration calls in a row. ' +
  'Quick lookups are fine inline; but if the exploration is repetitive or ' +
  'broad, delegate it: spawn a `subagent` with a focused TASK / EXPECTED ' +
  'OUTCOME / MUST DO / MUST NOT DO / CONTEXT prompt (see ' +
  '.agent/workflows/delegate-task.md) instead of grinding inline.'

/**
 * Per-agent nudging state, keyed by the live agent object (WeakMap: object
 * lifetime bounds the entry, no disposal listener needed — same as
 * repeat-tool-reminder).
 */
const state = new WeakMap()

export function apply(ctx, config = {}) {
  const maxReminders = config.maxReminders ?? DEFAULTS.maxReminders

  ctx.on('tools/post-execute', async (exec, _result, next) => {
    const downstream = await next()
    const agent = exec.agent
    if (!agent) return downstream

    let s = state.get(agent)
    if (!s) {
      s = { agentUsed: false, reminded: 0 }
      state.set(agent, s)
    }

    if (AGENT_TOOLS.has(exec.name)) {
      s.agentUsed = true
      return downstream
    }
    if (!SEARCH_TOOLS.has(exec.name) || s.agentUsed || s.reminded >= maxReminders) {
      return downstream
    }

    s.reminded += 1
    // additionalContexts are MESSAGES (they are appended as user/message):
    // a bare {source, text} shape yields content: null and crashes the LLM
    // serializer with "reading 'some'" — build a real user message instead.
    const additionalContexts = [
      createUserMessage({
        content: [{ type: 'text', text: REMINDER_TEXT }],
        source: { kind: 'plugin', plugin: 'agent-usage-reminder', form: 'instructions' },
      }),
      ...(downstream.additionalContexts ?? []),
    ]
    return { ...downstream, additionalContexts }
  })

  // A fresh user turn resets the nudge counter for that agent.
  ctx.on('agent/pre-step', ({ agent, messages }, next) => {
    if (messages?.some((m) => m.role === 'user' || m.kind === 'user' || m.source?.kind === 'user')) {
      state.delete(agent)
    }
    return next()
  })
}
