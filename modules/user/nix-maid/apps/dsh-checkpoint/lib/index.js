/**
 * dsh-checkpoint: context checkpoint / soft rewind (ported from omp).
 *
 * Plan: docs/howto/agent-deferred.ru.md §3. checkpoint stores a session-scoped
 * marker before exploratory work; rewind returns the concise report as a
 * synthetic instruction, replacing intermediate exploration in the model's
 * working context. v1 is SOFT: no history surgery — the model is told to
 * forget intermediate tool calls and continue from the report.
 */

import { defineTool } from '@deepseek-ai/dsh-tools'

export const name = 'dsh-checkpoint'
export const inject = ['tools']

const POINTS = new Map() // sessionId -> { note, createdAt }

function sessionKey(exec) {
  const sid = exec && exec.agent && exec.agent.session && exec.agent.session.id
  return sid || 'default'
}

const REWIND_GUIDANCE = function (note, report) {
  return 'Checkpoint rewind: exploration up to checkpoint ' + (note ? JSON.stringify(note) : '') +
    ' is replaced by the report below. Do NOT re-read or re-run the intermediate investigation; ' +
    'continue the task from this report as your current ground truth.\n\nREPORT:\n' + report
}

function checkpointTool() {
  return defineTool({
    name: 'checkpoint',
    description: 'Set a context checkpoint before exploratory work. Later call rewind with a concise ' +
      'report to replace the intermediate exploration in context (soft rewind).',
    parameters: {
      note: { type: 'string', description: 'Short label for the checkpoint.' },
    },
    output: {
      schema: { type: 'object', additionalProperties: true },
      render: function (_a, v) { return [{ type: 'text', text: JSON.stringify(v) }] },
    },
    isConcurrencySafe: function () { return true },
    timeoutMs: 5000,
    async execute(args, exec) {
      const sid = sessionKey(exec)
      const note = args.note ? String(args.note) : null
      POINTS.set(sid, { note: note, createdAt: Date.now() })
      return { ok: true, note: note, hint: 'Call rewind(report) after the exploration.' }
    },
  })
}

function rewindTool() {
  return defineTool({
    name: 'rewind',
    description: 'End the active checkpoint: replace intermediate exploration in context with a concise ' +
      'factual report. Include key findings, decisions, unresolved risks. The model continues from this ' +
      'report and does not re-read the intermediate investigation.',
    parameters: {
      report: { type: 'string', required: true, description: 'Concise factual report (findings, decisions, risks).' },
    },
    output: {
      schema: { type: 'object', additionalProperties: true },
      render: function (_a, v) { return [{ type: 'text', text: v.guidance || JSON.stringify(v) }] },
    },
    isConcurrencySafe: function () { return true },
    timeoutMs: 5000,
    async execute(args, exec) {
      const sid = sessionKey(exec)
      const point = POINTS.get(sid)
      POINTS.delete(sid)
      if (!point) {
        return { ok: true, rewound: false, note: 'no active checkpoint' }
      }
      return {
        ok: true,
        rewound: true,
        note: point.note,
        guidance: REWIND_GUIDANCE(point.note, String(args.report || '')),
      }
    },
  })
}

export function apply(ctx) {
  ctx.tools.register(checkpointTool())
  ctx.tools.register(rewindTool())
  ctx.effect(function () {
    return function () { POINTS.clear() }
  }, name + ': shutdown')
}
