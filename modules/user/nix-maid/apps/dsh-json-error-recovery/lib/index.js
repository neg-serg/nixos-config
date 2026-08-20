/**
 * dsh-json-error-recovery: corrective reminder after failed edit/write tools.
 *
 * Harness hook from oh-my-opencode backlog ("edit/json-error-recovery"):
 * when the model's previous step hit a tool error on edit/write/ast-grep
 * (JSON parse failure, hash mismatch, invalid args), inject one short
 * corrective user message on the next agent/pre-step instead of letting the
 * agent loop blindly retry.
 *
 * Mechanism (mirrors dsh-ttsr / dsh-advisor): scan the tail of the session
 * messages for a tool result whose state is error or whose content mentions
 * a JSON/parse/hash failure; then prepend a compact hint to the next step.
 * Per-session rate cap (MAX_PER_SESSION) avoids nagging loops.
 */

import { createUserMessage } from '@deepseek-ai/dsh-llm'

export const name = 'json-error-recovery'
export const inject = []

const MAX_PER_SESSION = 3
const TARGET_TOOLS = new Set(['edit', 'write', 'str_replace_editor', 'ast_grep', 'hashline_edit'])
const ERROR_PATTERNS = [
  /(JSON|json).*(parse|invalid|unexpected|expected)/,
  /hash mismatch|hashline/i,
  /must match exactly|old_string|appear exactly once/i,
  /ToolCallError|tool call failed|tool error/i,
]

function lastToolFailure(messages) {
  const list = Array.isArray(messages) ? messages : []
  for (let i = list.length - 1; i >= 0; i -= 1) {
    const m = list[i]
    // tool/result events carry the tool name + result/error
    const name = m?.toolName ?? m?.name ?? m?.tool ?? ''
    if (!TARGET_TOOLS.has(name)) continue
    const text = JSON.stringify(m?.result ?? m?.error ?? m?.content ?? '').slice(0, 2000)
    if (!text) continue
    if (m?.error || m?.state === 'error') return { tool: name, text }
    for (const re of ERROR_PATTERNS) if (re.test(text)) return { tool: name, text: text.slice(0, 500) }
  }
  return null
}

const HINTS = {
  edit: 'Правка не прошла: проверь, что old_string существует и уникален (читай файл заново перед edit), и что JSON-аргументы валидны. Не повторяй вслепую — сначала read. [json-error-recovery]',
  write: 'Запись не прошла: проверь JSON-аргументы и путь; перечитай файл перед повтором. [json-error-recovery]',
  str_replace_editor: 'str_replace не прошёл: old_str должен совпадать ровно один раз — перечитай файл и уточни контекст. [json-error-recovery]',
  ast_grep: 'ast-grep не прошёл: проверь паттерн/rewrite и метапеременные; preview (apply:false) перед применением. [json-error-recovery]',
  hashline_edit: 'hashline-правка отклонена: файл изменился с момента чтения — перечитай (read_hashline) и повтори с новыми якорями. [json-error-recovery]',
}

export function apply(ctx) {
  const fired = new Map()
  ctx.on('agent/pre-step', async ({ agent, messages }, next) => {
    const decision = await next()
    if (decision.kind === 'reject') return decision
    const sid = agent && agent.session ? agent.session.id : 'default'
    const fail = lastToolFailure(messages || decision.messages)
    if (fail === null) return decision
    const count = fired.get(sid) || 0
    if (count >= MAX_PER_SESSION) return decision
    fired.set(sid, count + 1)
    const hint = HINTS[fail.tool] || 'Инструмент вернул ошибку: прочитай сообщение об ошибке и исправь аргументы перед повтором. [json-error-recovery]'
    return {
      ...decision,
      messages: [...decision.messages, createUserMessage({
        content: [{ type: 'text', text: hint }],
        source: { kind: 'plugin', plugin: 'json-error-recovery' },
      })],
    }
  })
}
