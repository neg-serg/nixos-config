/**
 * dsh-task-resume-info: restore task context after session resume/fork.
 *
 * Harness hook from oh-my-opencode backlog ("task-resume-info"): when a
 * session is re-seeded (resume or fork, `session/end-seed` event), the model
 * restarts with a compacted/replayed history and often loses the thread of
 * what was being done. On the first pre-step after such a reseed we inject
 * one user-role reminder with the pending todo list and the last few user
 * asks, so the agent can continue rather than re-ask.
 *
 * Mechanism: session/event listener records sessions that just reseeded
 * (dedup: one injection per reseed); agent/pre-step consumes the mark for
 * that session and injects the folded context.
 */

import { createUserMessage } from '@deepseek-ai/dsh-llm'

export const name = 'dsh-task-resume-info'
export const inject = []

const MAX_USER_ASKS = 3

function foldTodos(session) {
  const events = Array.from((session && session.events) || [])
  for (let i = events.length - 1; i >= 0; i -= 1) {
    const e = events[i]
    if (e && e.type === 'todo/write' && Array.isArray(e.data?.todos)) {
      const pending = e.data.todos.filter((t) => t && t.status !== 'completed')
      if (pending.length === 0) return ''
      return pending.map((t) => '- [ ] ' + t.content).join('\n')
    }
  }
  return ''
}

function lastUserAsks(session) {
  const events = Array.from((session && session.events) || [])
  const asks = []
  for (let i = events.length - 1; i >= 0 && asks.length < MAX_USER_ASKS; i -= 1) {
    const e = events[i]
    if (!e || e.type !== 'assistant/message') continue
    const role = e.data?.message?.role
    if (role !== 'user') continue
    const c = e.data.message.content
    const text = Array.isArray(c) ? c.map((b) => (b && b.text) || '').join(' ').trim() : ''
    if (text !== '') asks.unshift(text.slice(0, 200))
  }
  return asks
}

export function apply(ctx) {
  const pendingReseed = new Set()
  ctx.on('session/event', function (session, event) {
    if (!session || !event) return
    if (event.type !== 'session/end-seed') return
    pendingReseed.add(session.id)
  })
  ctx.on('agent/pre-step', async ({ agent, messages }, next) => {
    const decision = await next()
    if (decision.kind === 'reject') return decision
    const agentObj = agent
    const session = agentObj && agentObj.session
    if (!session) return decision
    if (!pendingReseed.has(session.id)) return decision
    pendingReseed.delete(session.id)
    const todos = foldTodos(session)
    const asks = lastUserAsks(session)
    if (todos === '' && asks.length === 0) return decision
    const lines = ['[task-resume-info] Сессия восстановлена (resume/fork). Контекст задачи:']
    if (asks.length > 0) lines.push('Последние запросы пользователя:', ...asks.map((a) => '  > ' + a))
    if (todos !== '') lines.push('Незакрытые todo:', todos)
    lines.push('Продолжай с последнего незакрытого пункта; не переспрашивай то, что уже решено.')
    return {
      ...decision,
      messages: [...decision.messages, createUserMessage({
        content: [{ type: 'text', text: lines.join('\n') }],
        source: { kind: 'plugin', plugin: 'task-resume-info' },
      })],
    }
  })
}
