/**
 * dsh-memory-extractor: session-end memory extraction for DSH memento.
 *
 * v2: hooks session/end-seed and compaction/end, folds a BOUNDED transcript,
 * and runs the stage-one LLM extraction (memory-extract.md) through the LOCAL
 * Ollama endpoint (http://127.0.0.1:11434) — no plugin model service needed.
 * The parsed JSON (rollout_summary/raw_memory) is written to memento as an
 * '[extract]' agent/workspace entry; on any LLM failure the raw
 * '[draft-extract]' transcript is written instead, so durable context always
 * survives the session.
 *
 * Config (cordis): { endpoint?, model?, timeoutMs?, enabled? }
 *   endpoint — default http://127.0.0.1:11434/api/chat
 *   model    — default 'qwen3dot5:latest' (small/fast; raise for quality)
 *   timeoutMs— default 45000
 *   enabled  — default true; false keeps the v1 draft-only behavior
 *
 * Design: /etc/nixos/docs/howto/designs/memory-pipeline.md.
 */

export const name = 'dsh-memory-extractor'

export const inject = ['memory']

const MAX_CHARS = 4000
const NL = String.fromCharCode(10)
const DEFAULT_ENDPOINT = 'http://127.0.0.1:11434/api/chat'
const DEFAULT_MODEL = 'qwen3dot5:latest'
const DEFAULT_TIMEOUT = 45000
const PROMPT_PATH = '/etc/nixos/.agent/prompts/memory-extract.md'

/** Compact built-in fallback when the prompt file is unavailable (same contract). */
const FALLBACK_PROMPT = 'You are the stage-one memory extractor for a coding agent harness. Given a rollout transcript, return STRICT JSON only, no markdown, no prose: {\"rollout_summary\": \"string <=500 chars\", \"rollout_slug\": \"string|null\", \"raw_memory\": \"string\"}. raw_memory: markdown bullets \"- [slug] durable fact/decision/constraint/pitfall\". Keep: environment invariants, decisions with rationale, reproducible workflows, pitfalls and resolved failures, user corrections. Drop: chatter, noise, secrets NEVER. No durable signal -> empty summary/raw_memory and null slug.'

/** Read the real stage-one prompt, falling back to the compact built-in. */
async function loadPrompt() {
  try {
    const { readFile } = await import('node:fs/promises')
    const text = await readFile(PROMPT_PATH, 'utf8')
    return typeof text === 'string' && text.trim() !== '' ? text : FALLBACK_PROMPT
  } catch {
    return FALLBACK_PROMPT
  }
}

/**
 * Parse the model reply as JSON, tolerating markdown fences and stray prose.
 * @returns the parsed object, or null when no JSON object could be extracted.
 */
function parseModelJson(content) {
  let text = String(content || '').trim()
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/)
  if (fenced) text = fenced[1].trim()
  try {
    const parsed = JSON.parse(text)
    return parsed && typeof parsed === 'object' ? parsed : null
  } catch {
    const start = text.indexOf('{')
    const end = text.lastIndexOf('}')
    if (start !== -1 && end > start) {
      try {
        const parsed = JSON.parse(text.slice(start, end + 1))
        return parsed && typeof parsed === 'object' ? parsed : null
      } catch {
        return null
      }
    }
    return null
  }
}

/** POST one non-streaming chat completion to the local Ollama endpoint. */
async function callOllama(endpoint, model, prompt, transcript, timeoutMs) {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), timeoutMs)
  try {
    const res = await fetch(endpoint, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      signal: controller.signal,
      body: JSON.stringify({
        model,
        stream: false,
        options: { temperature: 0 },
        messages: [
          { role: 'system', content: prompt },
          { role: 'user', content: 'Rollout transcript:\n' + transcript },
        ],
      }),
    })
    if (!res.ok) throw new Error('ollama HTTP ' + res.status)
    const data = await res.json()
    const content = data && data.message && data.message.content
    if (typeof content !== 'string' || content === '') throw new Error('ollama: empty response')
    return parseModelJson(content)
  } finally {
    clearTimeout(timer)
  }
}

/** Fold one session event into a flat text line. */
function eventText(event) {
  if (!event || typeof event !== 'object') return ''
  const data = event.data
  if (!data || typeof data !== 'object') return ''
  if (Array.isArray(data.content)) {
    return data.content.map(function (b) { return typeof b === 'string' ? b : (b && b.text) || '' }).join(' ')
  }
  if (typeof data.message === 'object' && data.message) {
    const c = data.message.content
    if (Array.isArray(c)) return c.map(function (b) { return (b && b.text) || '' }).join(' ')
    if (typeof data.message.text === 'string') return data.message.text
  }
  if (typeof data.name === 'string') return data.name + ' ' + String(data.arguments || '')
  if (Array.isArray(data.todos)) return data.todos.map(function (t) { return '- ' + t.content }).join(' ')
  if (typeof data.text === 'string') return data.text
  return ''
}

/** Bound the session event list to the last 400 events, one line each. */
function foldTranscript(session) {
  const parts = []
  const events = Array.from((session && session.events) || [])
  const limit = Math.max(0, events.length - 400) // last 400 events
  for (let i = limit; i < events.length; i++) {
    const text = eventText(events[i])
    if (text !== '') parts.push(events[i].type + ': ' + text.slice(0, 300))
  }
  return parts.join(NL)
}

/**
 * Run the LLM step and write the extract; fall back to the raw draft on any
 * failure or when the model reports no durable signal.
 */
async function extractAndStore(ctx, opts) {
  const { session, transcript, endpoint, model, timeoutMs, enabled } = opts
  const bounded = transcript.slice(0, MAX_CHARS)
  const writeDraft = async function () {
    const text = '[draft-extract] session=' + session.id + NL + bounded
    await ctx.memory.add({ track: 'agent', scope: 'workspace', text })
  }
  try {
    if (enabled) {
      const prompt = await loadPrompt()
      const parsed = await callOllama(endpoint, model, prompt, bounded, timeoutMs)
      const summary = parsed && typeof parsed.rollout_summary === 'string' ? parsed.rollout_summary.trim() : ''
      const raw = parsed && typeof parsed.raw_memory === 'string' ? parsed.raw_memory.trim() : ''
      if (summary !== '' || raw !== '') {
        const slug = parsed && typeof parsed.rollout_slug === 'string' && parsed.rollout_slug.trim() !== ''
          ? parsed.rollout_slug.trim()
          : 'session-' + session.id
        const text = '[extract] session=' + session.id + ' slug=' + slug + NL + summary + (raw !== '' ? NL + raw : '')
        await ctx.memory.add({ track: 'agent', scope: 'workspace', text })
        if (ctx.logger && typeof ctx.logger.debug === 'function') {
          ctx.logger.debug('[dsh-memory-extractor] extract for ' + session.id + ' (' + text.length + ' chars)')
        }
        return
      }
      if (ctx.logger && typeof ctx.logger.debug === 'function') {
        ctx.logger.debug('[dsh-memory-extractor] LLM reported no durable signal; keeping draft for ' + session.id)
      }
    }
    await writeDraft()
  } catch (err) {
    if (ctx.logger && typeof ctx.logger.warn === 'function') {
      ctx.logger.warn('[dsh-memory-extractor] LLM step failed (' + String(err) + '); writing draft for ' + session.id)
    }
    try {
      await writeDraft()
    } catch (err2) {
      if (ctx.logger && typeof ctx.logger.warn === 'function') {
        ctx.logger.warn('[dsh-memory-extractor] draft also failed: ' + String(err2))
      }
    }
  }
}

export function apply(ctx) {
  const config = (ctx && ctx.config) || {}
  const endpoint = config.endpoint || DEFAULT_ENDPOINT
  const model = config.model || DEFAULT_MODEL
  const timeoutMs = config.timeoutMs || DEFAULT_TIMEOUT
  const enabled = config.enabled !== false
  ctx.on('session/event', function (session, event) {
    if (!session || !event) return
    if (event.type !== 'session/end-seed' && event.type !== 'compaction/end') return
    try {
      const transcript = foldTranscript(session)
      if (transcript === '') return
      void extractAndStore(ctx, { session, transcript, endpoint, model, timeoutMs, enabled })
    } catch (err) {
      if (ctx.logger && typeof ctx.logger.warn === 'function') {
        ctx.logger.warn('[dsh-memory-extractor] ' + String(err))
      }
    }
  })
}
