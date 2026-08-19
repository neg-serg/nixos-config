/**
 * dsh-memory-extractor: session-end memory extraction for DSH memento.
 *
 * v1 scope (honest): hooks session/end-seed, folds a BOUNDED transcript of the
 * session events (messages, tool names, todo snapshots) and writes it into
 * memento as a '[draft-extract]' agent/workspace entry, so the durable context
 * survives the session. The stage-one LLM extraction (see
 * /etc/nixos/.agent/prompts/memory-extract.md) needs a model-call service that
 * is NOT exposed to plugins in this DSH build (dsh-memento itself only
 * truncates compaction summaries, no LLM) — see TODO below.
 *
 * Design: /etc/nixos/docs/howto/designs/memory-pipeline.md.
 */

export const name = 'dsh-memory-extractor'

const MAX_CHARS = 4000
const NL = String.fromCharCode(10)

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

export function apply(ctx) {
  ctx.on('session/event', function (session, event) {
    if (!session || !event) return
    if (event.type !== 'session/end-seed' && event.type !== 'compaction/end') return
    try {
      const transcript = foldTranscript(session)
      if (transcript === '') return
      const text = '[draft-extract] session=' + session.id + NL + transcript.slice(0, MAX_CHARS)
      if (ctx.memory && typeof ctx.memory.add === 'function') {
        void ctx.memory.add({ track: 'agent', scope: 'workspace', text }).catch(function () {})
      } else if (ctx.logger && typeof ctx.logger.debug === 'function') {
        ctx.logger.debug('[dsh-memory-extractor] draft-extract for ' + session.id + ' (' + text.length + ' chars)')
      }
      // TODO(LLM step): run /etc/nixos/.agent/prompts/memory-extract.md over the
      // transcript and write the parsed JSON (rollout_summary/raw_memory) instead
      // of the raw draft. Needs a model-call service exposed to plugins — none in
      // this DSH build; memento proposals are truncation-only.
    } catch (err) {
      if (ctx.logger && typeof ctx.logger.warn === 'function') ctx.logger.warn('[dsh-memory-extractor] ' + String(err))
    }
  })
}
