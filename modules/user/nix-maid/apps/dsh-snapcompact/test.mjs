/**
 * Offline functional test for dsh-snapcompact.
 *
 * Run it from the profile's node_modules so `@deepseek-ai/dsh-llm` resolves,
 * exactly like the other plugin tests:
 *
 *   cp -r modules/user/nix-maid/apps/dsh-snapcompact ~/.dsh/profiles/tui/node_modules/
 *   cd ~/.dsh/profiles/tui && node node_modules/dsh-snapcompact/test.mjs
 *
 * What it checks:
 *   1. compaction/start + compaction/summary append one JSON frame per
 *      compaction to <dir>/<session>.jsonl, with the shadowed range, seqs,
 *      token count, provider and model from the summary event;
 *   2. the next agent/pre-step injects exactly one [snapcompact] user message
 *      naming the range and the frame file — and only once;
 *   3. a second compaction appends a second line (no rewriting);
 *   4. enabled: false writes nothing and injects nothing.
 */

import assert from 'node:assert/strict'
import { mkdtempSync, readFileSync, existsSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

const mod = await import('./lib/index.js')

function makeCtx(config) {
  const handlers = new Map()
  const ctx = { on: (event, fn) => handlers.set(event, fn) }
  return {
    ctx,
    start: () => mod.apply(ctx, config),
    emit: (event, session, data) => handlers.get('session/event')(session, { type: event, data }),
    preStep: (session) =>
      handlers.get('agent/pre-step')({ agent: { session } }, async () => ({ messages: [] })),
  }
}

const summary = (compactionId, start, end, tokens) => ({
  compactionId,
  summary: [],
  shadowedRange: { start, end },
  shadowedSeqs: [start + 1, start + 2],
  shadowedTokenCount: tokens,
  provider: 'deepseek',
  model: 'deepseek-chat',
})

// 1–3: enabled by default
{
  const dir = mkdtempSync(join(tmpdir(), 'snapcompact-'))
  const h = makeCtx({ dir })
  h.start()

  const session = { id: 'sess-1' }
  h.emit('compaction/start', session, { compactionId: 'c1', turn: 7 })
  h.emit('compaction/summary', session, summary('c1', 10, 40, 1234))

  const file = join(dir, 'sess-1.jsonl')
  assert.ok(existsSync(file), 'the frame file must exist after a compaction summary')
  const frames = readFileSync(file, 'utf8').trim().split('\n').map((l) => JSON.parse(l))
  assert.equal(frames.length, 1)
  assert.deepEqual(frames[0].shadowedRange, { start: 10, end: 40 })
  assert.equal(frames[0].shadowedTokenCount, 1234)
  assert.equal(frames[0].provider, 'deepseek')
  assert.equal(frames[0].model, 'deepseek-chat')
  assert.equal(frames[0].turn, 7)

  const decision = await h.preStep(session)
  assert.equal(decision.messages.length, 1, 'one note must be injected')
  const text = decision.messages[0].content[0].text
  assert.match(text, /\[snapcompact\]/)
  assert.match(text, /10\.\.40/)
  assert.match(text, /1234 tokens/)
  assert.match(text, new RegExp(file.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')))

  const second = await h.preStep(session)
  assert.equal(typeof second, 'object', 'pre-step must always return a decision')
  assert.equal(second.messages.length, 0, 'the note must be one-shot')

  // 3: a second compaction appends instead of rewriting
  h.emit('compaction/start', session, { compactionId: 'c2', turn: 9 })
  h.emit('compaction/summary', session, summary('c2', 41, 60, 99))
  h.emit('compaction/end', session, { compactionId: 'c2', turn: 9 })
  const frames2 = readFileSync(file, 'utf8').trim().split('\n')
  assert.equal(frames2.length, 2, 'the second compaction appends a frame')
}

// 4: disabled
{
  const dir = mkdtempSync(join(tmpdir(), 'snapcompact-off-'))
  const h = makeCtx({ dir, enabled: false })
  h.start()
  const session = { id: 'sess-2' }
  h.emit('compaction/start', session, { compactionId: 'c1', turn: 1 })
  h.emit('compaction/summary', session, summary('c1', 1, 2, 3))
  assert.equal(existsSync(join(dir, 'sess-2.jsonl')), false, 'disabled: no frame file')
  const decision = await h.preStep(session)
  assert.equal(decision.messages.length, 0, 'disabled: no note')
}

console.log('dsh-snapcompact: ok')
