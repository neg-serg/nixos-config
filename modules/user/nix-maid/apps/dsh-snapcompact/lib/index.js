/**
 * dsh-snapcompact: snapshot frames for session compaction.
 *
 * Mechanism (AGENT plane, same seam as dsh-compaction-todo-preserver): the
 * harness emits `compaction/start`, `compaction/summary` and `compaction/end`
 * as session events. The summary carries everything a snapshot frame needs —
 * `shadowedRange` (start/end seq), `shadowedSeqs`, `shadowedTokenCount`,
 * `provider`, `model` — so the plugin appends one JSON line per compaction to
 * `$DSH_HOME/snapcompact/<sessionID>.jsonl` and, once, injects a short user
 * message at the next `agent/pre-step` pointing at that frame.
 *
 * Deliberately narrow v1: the plugin only *reads* session events and writes to
 * its own file. It never appends session events, so a bug here cannot corrupt a
 * session log or a compaction — the worst case is a missing note or a stale
 * file under `~/.dsh/snapcompact/`. Live-session evaluation is the phase-3 item
 * of docs/howto/agent-deferred.md §9; this is the phase-2 prototype.
 *
 * Config (cordis patch row): `{ enabled?, note?, dir? }`.
 */

import { appendFileSync, mkdirSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

import { createUserMessage } from '@deepseek-ai/dsh-llm'

export const name = 'dsh-snapcompact'

const DEFAULTS = { enabled: true, note: true, dir: null }

function frameDir(config) {
  if (config.dir) return config.dir
  const home = process.env.DSH_HOME || join(homedir(), '.dsh')
  return join(home, 'snapcompact')
}

/** Safe file name for a session id (ids are already tame, but be defensive). */
function frameFile(dir, sessionID) {
  return join(dir, String(sessionID).replace(/[^A-Za-z0-9._-]/g, '_') + '.jsonl')
}

export function apply(ctx) {
  const config = { ...DEFAULTS, ...(ctx.config ?? {}) }
  const dir = frameDir(config)
  /** sessionID -> { compactionId, turn, note } */
  const pending = new Map()

  ctx.on('session/event', (session, event) => {
    if (!config.enabled || !session || !event) return
    const sid = session.id
    if (!sid) return
    const data = event.data ?? {}

    if (event.type === 'compaction/start') {
      pending.set(sid, { compactionId: data.compactionId ?? null, turn: data.turn ?? null, note: null })
      return
    }

    if (event.type === 'compaction/summary') {
      const state = pending.get(sid) ?? { compactionId: null, turn: null, note: null }
      const frame = {
        v: 1,
        at: new Date().toISOString(),
        session: sid,
        compactionId: data.compactionId ?? state.compactionId,
        turn: state.turn,
        provider: data.provider ?? null,
        model: data.model ?? null,
        shadowedRange: data.shadowedRange ?? null,
        shadowedSeqs: data.shadowedSeqs ?? [],
        shadowedTokenCount: data.shadowedTokenCount ?? null,
      }
      let file = null
      try {
        mkdirSync(dir, { recursive: true })
        file = frameFile(dir, sid)
        appendFileSync(file, JSON.stringify(frame) + '\n')
      } catch {
        // A read-only or full disk must not break the agent loop.
      }
      if (config.note) {
        const seqs = frame.shadowedSeqs.length
        const range = frame.shadowedRange
          ? `${frame.shadowedRange.start}..${frame.shadowedRange.end}`
          : 'unknown'
        state.note =
          `[snapcompact] compaction ${frame.compactionId ?? '(unknown)'} shadowed ` +
          `${range} (${frame.shadowedTokenCount ?? '?'} tokens, ${seqs} seqs) via ` +
          `${frame.provider ?? '?'}/${frame.model ?? '?'}; snapshot frame: ${file ?? '(not written)'}`
      }
      pending.set(sid, state)
      return
    }

    if (event.type === 'compaction/end' || event.type === 'session/end-seed') {
      // Keep the note for the next pre-step; compaction/end carries an optional
      // error, which is not worth a separate message.
      return
    }
  })

  ctx.on('agent/pre-step', async function ({ agent }, next) {
    const decision = await next()
    if (!config.enabled || !config.note) return decision
    const sid = agent && agent.session ? agent.session.id : null
    const state = sid ? pending.get(sid) : null
    if (!state || !state.note) return decision
    const note = state.note
    state.note = null
    return {
      ...decision,
      messages: [
        ...(decision.messages ?? []),
        createUserMessage({
          content: [{ type: 'text', text: note }],
          source: { kind: 'plugin', plugin: 'snapcompact' },
        }),
      ],
    }
  })
}
