/**
 * dsh-delegate-task-retry: retry hint after a failed subagent delegation.
 *
 * Harness hook from oh-my-opencode backlog ("delegate-task-retry"): when the
 * last step's tool/result for subagent / subagent_fork is an error, inject
 * one user-role hint on the next pre-step so the agent retries the delegation
 * (with the same or a tightened prompt) instead of silently moving on.
 *
 * Mechanism: scan the tail of the session messages for tool/result with
 * isError where the matching tool/call name is a delegation tool; inject once
 * per failed delegation (keyed by callId), capped per session.
 */

import { createUserMessage } from '@deepseek-ai/dsh-llm'

export const name = 'dsh-delegate-task-retry'
export const inject = []

const DELEGATE_TOOLS = new Set(['subagent', 'subagent_fork'])
const MAX_PER_SESSION = 4

function lastDelegationFailure(messages) {
  const list = Array.isArray(messages) ? messages : []
  // messages may be event-like objects or {role, content}; scan backwards for
  // a tool/result error whose callId matches a preceding delegation tool/call.
  const results = new Map()
  for (let i = list.length - 1; i >= 0; i -= 1) {
    const m = list[i]
    const type = m?.type ?? m?.kind ?? ''
    const name = m?.toolName ?? m?.name ?? m?.tool ?? ''
    if (type === 'tool/result' || type === 'tool_result' || (m?.isError !== undefined && m?.content?.[0]?.isError)) {
      const isErr = m?.isError === true || m?.content?.[0]?.isError === true
      const callId = m?.callId ?? m?.source?.callId ?? m?.id ?? ''
      if (isErr && callId !== '') results.set(callId, { tool: m?.toolName ?? m?.name ?? m?.tool ?? '', text: JSON.stringify(m).slice(0, 500) })
      continue
    }
    if (type === 'tool/call' || type === 'tool_call' || (name && m?.arguments !== undefined)) {
      const callId = m?.callId ?? m?.id ?? ''
      if (results.has(callId) && DELEGATE_TOOLS.has(name)) return { callId, tool: name, text: results.get(callId).text }
      continue
    }
    // plain message shape: {role:'assistant', content:[{tool_use_id, name, input}]}
    const c = m?.content
    if (Array.isArray(c)) {
      for (const block of c) {
        if (block?.type === 'tool_result' && block.isError) {
          const id = block.tool_use_id ?? ''
          if (id !== '') results.set(id, { tool: '', text: String(block.content ?? '').slice(0, 400) })
        }
      }
      for (const block of c) {
        if (block?.type === 'tool_use' && DELEGATE_TOOLS.has(block.name)) {
          const id = block.id ?? ''
          if (results.has(id)) return { callId: id, tool: block.name, text: results.get(id).text }
        }
      }
    }
  }
  return null
}

export function apply(ctx) {
  const fired = new Map()
  ctx.on('agent/pre-step', async ({ agent, messages }, next) => {
    const decision = await next()
    if (decision.kind === 'reject') return decision
    const sid = agent && agent.session ? agent.session.id : 'default'
    const fail = lastDelegationFailure(messages || decision.messages)
    if (fail === null) return decision
    const key = sid + ':' + fail.callId
    if (fired.has(key)) return decision
    const count = fired.size
    if (count >= MAX_PER_SESSION) return decision
    fired.set(key, true)
    const hint = 'Делегирование (' + fail.tool + ') завершилось ошибкой. Повтори вызов subagent с тем же промптом (или уточни его: добавь контекст/ограничения из ошибки). Не переходи к следующему шагу, пока делегация не вернёт результат. [delegate-task-retry]'
    return {
      ...decision,
      messages: [...decision.messages, createUserMessage({
        content: [{ type: 'text', text: hint }],
        source: { kind: 'plugin', plugin: 'delegate-task-retry' },
      })],
    }
  })
}
