/**
 * dsh-advisor: peer-shadow quality advisor for DSH (port of the omp advisor
 * pattern; design: /etc/nixos/docs/howto/agent-advisor.ru.md).
 *
 * Mechanism: on agent/pre-step (AGENT plane, like dsh-ttsr) every `interval`
 * steps the plugin ASYNCHRONOUSLY asks a LOCAL Ollama model for one short
 * concrete observation about the recent transcript. The model call never
 * blocks the agent loop: a non-empty reply is queued and injected as a user
 * message at the NEXT pre-step. Silence (empty/short replies) is dropped;
 * each session gets at most MAX_ADVICE_PER_SESSION advice lines.
 *
 * Config (cordis patch row): { endpoint?, model?, interval?, timeoutMs?,
 * enabled? } — endpoint default http://127.0.0.1:11434/api/chat,
 * model default qwen3:8b-q8_0 (benchmarked on odin).
 */

import { createUserMessage } from '@deepseek-ai/dsh-llm'

export const name = 'dsh-advisor'

const NL = String.fromCharCode(10)
const DEFAULT_ENDPOINT = 'http://127.0.0.1:11434/api/chat'
const DEFAULT_MODEL = 'qwen3:8b-q8_0'
const DEFAULT_INTERVAL = 8
const DEFAULT_TIMEOUT = 60000
const MAX_ADVICE_PER_SESSION = 5
const MAX_TRANSCRIPT = 4000
const WINDOW = 12

/** Advisor system prompt (compact adaptation of agent-advisor.ru.md). */
const SYSTEM_PROMPT = 'Ты — советник (advisor) поверх основного агента: защитник качества кода и точности исполнения запроса пользователя. Получаешь инкрементальный транскрипт последних шагов. Оспаривай преждевременное done, тонкую верификацию, пропущенные рассуждения. Флагуй дрейф от запроса пользователя немедленно. Предотвращай кроличьи норы и запечённые edge-case-ы. НЕ повторяй то, что агент уже знает: ошибки типов, диагностику, упавшие тесты, линт. НЕ утверждай конкретные значения для скрытых аргументов — только наблюдаемые факты. Сначала проверь (read/grep/glob), потом поднимай вопрос; после достаточного исследования предлагай подход или фикс, а не только предупреждение. Реплика: ОДНА короткая конкретная фраза. Когда сказать нечего — верни пустую строку. Отвечай на языке транскрипта. Без markdown, без пояснений, только сама реплика или пусто.'

/** Fold the last WINDOW messages into a bounded transcript line. */
function transcriptFromMessages(messages, maxLen) {
  const list = Array.isArray(messages) ? messages : []
  const parts = []
  for (let i = Math.max(0, list.length - WINDOW); i < list.length; i++) {
    const m = list[i]
    if (!m || typeof m !== 'object') continue
    const role = String((m.role || m.kind) || '').toLowerCase()
    let text = ''
    if (Array.isArray(m.content)) {
      text = m.content.map(function (b) { return (b && typeof b.text === 'string') ? b.text : '' }).join(' ').trim()
    } else if (typeof m.text === 'string') {
      text = m.text.trim()
    }
    if (text !== '') parts.push((role !== '' ? role : 'msg') + ': ' + text.slice(0, 300))
  }
  return parts.join(NL).slice(0, maxLen)
}

/** True when the model reply means nothing worth injecting. */
function looksLikeSilence(text) {
  const t = String(text || '').trim()
  if (t === '') return true
  if (t.length < 8) return true
  return /^(\s*\(?молч|нет замечан|нечего сказать|nothing|no comment|silence|—|\s*$)/i.test(t)
}

/** One non-streaming local Ollama call; returns a bounded advice or null. */
async function askAdvisor(endpoint, model, transcript, timeoutMs) {
  const controller = new AbortController()
  const timer = setTimeout(function () { controller.abort() }, timeoutMs)
  try {
    const res = await fetch(endpoint, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      signal: controller.signal,
      body: JSON.stringify({
        model,
        stream: false,
        options: { temperature: 0.3 },
        messages: [
          { role: 'system', content: SYSTEM_PROMPT },
          { role: 'user', content: 'Recent transcript:\n' + transcript },
        ],
      }),
    })
    if (!res.ok) throw new Error('ollama HTTP ' + res.status)
    const data = await res.json()
    const content = data && data.message ? String(data.message.content || '').trim() : ''
    if (looksLikeSilence(content)) return null
    return content.replace(/^\[?advisor\]?:?\s*/i, '').slice(0, 300)
  } finally {
    clearTimeout(timer)
  }
}

export function apply(ctx, config) {
  const c = (config && typeof config === 'object') ? config : {}
  const endpoint = c.endpoint || DEFAULT_ENDPOINT
  const model = c.model || DEFAULT_MODEL
  const interval = Number(c.interval) > 0 ? Number(c.interval) : DEFAULT_INTERVAL
  const timeoutMs = Number(c.timeoutMs) > 0 ? Number(c.timeoutMs) : DEFAULT_TIMEOUT
  const enabled = c.enabled !== false
  const perSession = new Map()

  ctx.on('agent/pre-step', async function ({ agent, messages }, next) {
    const decision = await next()
    if (!enabled || decision.kind === 'reject') return decision
    const sid = agent && agent.session ? agent.session.id : 'default'
    let st = perSession.get(sid)
    if (!st) { st = { advice: null, step: 0, calls: 0, inFlight: false }; perSession.set(sid, st) }
    st.step += 1
    if (st.advice !== null) {
      const advice = st.advice
      st.advice = null
      return {
        ...decision,
        messages: [...decision.messages, createUserMessage({
          content: [{ type: 'text', text: '[advisor] ' + advice }],
          source: { kind: 'plugin', plugin: 'advisor' },
        })],
      }
    }
    if (st.step % interval !== 0 || st.calls >= MAX_ADVICE_PER_SESSION || st.inFlight) return decision
    const transcript = transcriptFromMessages(messages || decision.messages, MAX_TRANSCRIPT)
    if (transcript === '') return decision
    st.calls += 1
    st.inFlight = true
    void askAdvisor(endpoint, model, transcript, timeoutMs).then(function (advice) {
      const cur = perSession.get(sid)
      if (cur) {
        cur.inFlight = false
        if (advice !== null) cur.advice = advice
      }
    }).catch(function () {
      const cur = perSession.get(sid)
      if (cur) cur.inFlight = false
    })
    return decision
  })
}
