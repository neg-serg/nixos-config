/**
 * dsh-notepad-write-guard: protect .agent/notepads/** from accidental edits.
 *
 * Harness hook from oh-my-opencode backlog ("notepad-write-guard"): notepads
 * are the plan's cumulative memory (.agent/workflows/notepads.md) and should
 * only be appended by the user or a deliberate subagent, never rewritten by
 * the main agent's edit/write tools. We deny write/edit/str_replace_editor/
 * hashline_edit calls whose target path falls under a notepad directory, with
 * a reason that tells the agent to read + append instead.
 *
 * Mechanism: tools/pre-execute gate (around-dispatch cannot rewrite args, and
 * we do NOT want to rewrite — we want a hard deny). Listener returns
 * { kind: 'deny', reason } which the registry turns into a tool error.
 */

export const name = 'dsh-notepad-write-guard'
export const inject = []

const WRITE_TOOLS = new Set(['write', 'edit', 'str_replace_editor', 'hashline_edit', 'read_document'])
const NOTEPAD_MARKERS = ['.agent/notepads', 'notepads/']

function targetPath(exec) {
  const args = exec?.args ?? {}
  return args.path ?? args.file_path ?? args.pathname ?? ''
}

export function apply(ctx) {
  ctx.on('tools/pre-execute', async (exec, next) => {
    const decision = await next()
    if (decision.kind !== 'allow') return decision
    if (!WRITE_TOOLS.has(exec.name)) return decision
    const p = targetPath(exec)
    if (p === '') return decision
    const isNotepad = NOTEPAD_MARKERS.some((m) => p.includes(m))
    if (!isNotepad) return decision
    return {
      kind: 'deny',
      reason: 'notepad-write-guard: ' + p + ' is under .agent/notepads/ — notepad files are append-only plan memory. Read the file and update it via a deliberate append (or ask the user to edit it). Do not rewrite/delete notepad content.',
    }
  })
}
