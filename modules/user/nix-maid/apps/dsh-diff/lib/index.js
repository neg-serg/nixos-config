/**
 * dsh-diff: the diff-review surface.
 *
 * Two halves over one git call:
 *
 *  - the `show_diff` tool returns the patch and declares `card: "diff"` through
 *    `output.presentationMeta` + `presentResult`, which is the same presenter the
 *    edit-approval preview uses — so a UI renders structured red/green file
 *    diffs instead of a wall of text;
 *  - the `/diff` command gives the human a quick textual view (commands can only
 *    return text — `CommandResult` has no card).
 *
 * The diff is reconstructed from `git diff` patch text rather than by reading
 * the old and new file contents. That keeps the whole review to ONE subprocess
 * (one `git show` per changed file would be dozens), needs no filesystem service
 * and no sandbox bypass: for each file the unified patch already carries the
 * changed regions, and old/new are rebuilt from context+removed and
 * context+added lines. The card therefore shows the changed hunks, not the whole
 * file — which is what a review wants anyway.
 *
 * `presentationMeta` is pure and synchronous, so it is the parser: the canonical
 * value carries the patch string, and the presenter projection derives the
 * `FileDiff[]` from it.
 */

/** Cordis plugin name — must match the patch row / package name. */
export const name = 'dsh-diff'

/** Required services: tool + command registries and the subprocess seam. */
export const inject = ['tools', 'subprocess', 'commands']

/** Per-stream output cap; a huge working tree must not blow up a tool result. */
const MAX_BYTES = 512 * 1024

/** Cards are for reading: beyond this the patch is summarised, not rendered. */
const MAX_CARD_FILES = 40

const TOOL_NAME = 'show_diff'

const TARGETS = {
  worktree: { label: 'uncommitted changes', args: ['diff', 'HEAD'] },
  staged: { label: 'staged changes', args: ['diff', '--cached'] },
}

/** The patch header line that names the file a hunk block belongs to. */
const FILE_HEADER = /^diff --git "?a\/(.+?)"? "?b\/(.+?)"?$/

/**
 * Rebuild one `FileDiff` from a `git diff` block.
 *
 * Additions and removals are folded into two synthetic texts: the card renderer
 * diffs those again, which reproduces the same change with the same red/green
 * structure. `oldText` is null for a file that did not exist before (git says
 * `new file mode`), matching the presenter's contract for a create.
 */
export function parseHunkBlock(block) {
  const header = FILE_HEADER.exec(block.split('\n', 1)[0] ?? '')
  if (header === null) return null
  const path = header[2] === '/dev/null' ? header[1] : header[2]
  if (path === '/dev/null' || path === undefined) return null

  const isNew = /^new file mode /m.test(block)
  const isBinary = /^Binary files .* differ$/m.test(block)

  const oldLines = []
  const newLines = []
  let inHunk = false
  let added = 0
  let removed = 0

  // Patch text is newline-terminated, so splitting leaves a trailing empty
  // element; treating it as a context line would append a phantom line to both
  // sides of every rebuilt file.
  const lines = block.split('\n')
  if (lines.length > 0 && lines[lines.length - 1] === '') lines.pop()

  for (const line of lines) {
    if (line.startsWith('@@')) {
      inHunk = true
      continue
    }
    if (!inHunk) continue
    if (line.startsWith('+++') || line.startsWith('---')) continue
    if (line.startsWith('+')) {
      newLines.push(line.slice(1))
      added += 1
      continue
    }
    if (line.startsWith('-')) {
      oldLines.push(line.slice(1))
      removed += 1
      continue
    }
    if (line.startsWith('\\')) continue // "\ No newline at end of file"
    // Context line (leading space, or an empty line git emitted verbatim).
    const context = line.startsWith(' ') ? line.slice(1) : line
    oldLines.push(context)
    newLines.push(context)
  }

  return {
    path,
    oldText: isNew ? null : oldLines.join('\n'),
    newText: newLines.join('\n'),
    added,
    removed,
    binary: isBinary,
  }
}

/** Split a `git diff` output into per-file `FileDiff`s (pure). */
export function parsePatch(patch) {
  if (typeof patch !== 'string' || patch.trim() === '') return []
  const blocks = patch.split(/^(?=diff --git )/m).filter((block) => block.startsWith('diff --git '))
  const files = []
  for (const block of blocks) {
    const parsed = parseHunkBlock(block)
    if (parsed !== null) files.push(parsed)
  }
  return files
}

/** `git diff --stat`-like one-liner for a parsed file. */
function statLine(file) {
  if (file.binary) return `${file.path}  (binary)`
  return `${file.path}  +${file.added} −${file.removed}`
}

function summarise(files, target) {
  if (files.length === 0) return `dsh-diff: no ${target.label}`
  const added = files.reduce((sum, file) => sum + file.added, 0)
  const removed = files.reduce((sum, file) => sum + file.removed, 0)
  return `dsh-diff: ${files.length} file(s), +${added} −${removed} — ${target.label}`
}

function resolveTarget(args) {
  if (args?.staged === true) return TARGETS.staged
  if (typeof args?.ref === 'string' && args.ref !== '') {
    return { label: `changes vs ${args.ref}`, args: ['diff', args.ref] }
  }
  return TARGETS.worktree
}

/** One collected git invocation through the harness's own spawner. */
async function runGit(ctx, cwd, argv, signal) {
  let bin = 'git'
  if (typeof ctx.subprocess.resolveExecutable === 'function') {
    try {
      bin = await ctx.subprocess.resolveExecutable('git')
    } catch {
      /* fall through to the provider's PATH lookup */
    }
  }
  const handle = ctx.subprocess.spawn({
    argv: [bin, ...argv],
    cwd,
    stdio: {
      stdin: 'ignore',
      stdout: { maxBytes: MAX_BYTES },
      stderr: { maxBytes: MAX_BYTES },
    },
    graceMs: 5000,
    signal,
  })
  const outcome = await handle.done
  const stdout = handle.collected.stdout?.readFrom(0)?.text ?? ''
  const stderr = handle.collected.stderr?.readFrom(0)?.text ?? ''
  return { code: outcome.exitCode, stdout, stderr }
}

/** Untracked files never appear in `git diff`, so they are listed separately. */
async function untrackedFiles(ctx, cwd, signal) {
  const result = await runGit(ctx, cwd, ['status', '--porcelain=v1', '--untracked-files=all'], signal)
  if (result.code !== 0) return []
  return result.stdout
    .split('\n')
    .filter((line) => line.startsWith('?? '))
    .map((line) => line.slice(3))
}

/**
 * Run one review: the patch text plus the summary. Shared by the tool and the
 * command so both surfaces always agree.
 */
async function collect(ctx, cwd, args, signal) {
  const target = resolveTarget(args)
  const argv = [...target.args, '--no-color', '--no-ext-diff']
  if (typeof args?.path === 'string' && args.path !== '') argv.push('--', args.path)
  const result = await runGit(ctx, cwd, argv, signal)
  if (result.code !== 0) {
    return { ok: false, error: result.stderr.trim() || `git diff exited with ${result.code}` }
  }
  const files = parsePatch(result.stdout)
  const untracked = args?.staged === true ? [] : await untrackedFiles(ctx, cwd, signal)
  return { ok: true, target, patch: result.stdout, files, untracked }
}

function toolText(report) {
  const lines = [summarise(report.files, report.target)]
  for (const file of report.files.slice(0, MAX_CARD_FILES)) lines.push(statLine(file))
  if (report.files.length > MAX_CARD_FILES) lines.push(`… ${report.files.length - MAX_CARD_FILES} more file(s)`)
  if (report.untracked.length > 0) {
    lines.push('', `untracked (${report.untracked.length}):`)
    for (const path of report.untracked.slice(0, MAX_CARD_FILES)) lines.push(`  ${path}`)
  }
  if (report.files.length === 0 && report.untracked.length === 0) {
    lines.push('nothing to review')
  }
  return lines.join('\n')
}

export function apply(ctx) {
  ctx.tools.register({
    name: TOOL_NAME,
    description:
      'Show the uncommitted changes as a structured diff review: every changed file with its ' +
      'added/removed lines. Use it before summarising or committing work, or when the user asks ' +
      'what changed. Optionally narrow to a path, the index, or compare against a ref.',
    parameters: {
      type: 'object',
      properties: {
        path: { type: 'string', description: 'limit the review to one path (file or directory)' },
        staged: { type: 'boolean', description: 'review the index instead of the working tree' },
        ref: { type: 'string', description: 'compare against this ref (branch, tag, commit)' },
      },
      additionalProperties: false,
    },
    output: {
      schema: {
        type: 'object',
        properties: {
          summary: { type: 'string' },
          patch: { type: 'string' },
          files: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                path: { type: 'string' },
                added: { type: 'number' },
                removed: { type: 'number' },
                binary: { type: 'boolean' },
              },
              required: ['path', 'added', 'removed', 'binary'],
              additionalProperties: false,
            },
          },
          untracked: { type: 'array', items: { type: 'string' } },
        },
        required: ['summary', 'patch', 'files', 'untracked'],
        additionalProperties: false,
      },
      render: (_args, value) => [{ type: 'text', text: value.summary }],
      // Pure and synchronous: the card projection is derived from the patch.
      presentationMeta: (_args, value) => ({
        diffs: parsePatch(value.patch).slice(0, MAX_CARD_FILES).map((file) => ({
          path: file.path,
          oldText: file.oldText,
          newText: file.newText,
        })),
      }),
    },
    presentCall: (args) => ({
      card: 'generic',
      kind: 'read',
      title: `Review ${resolveTarget(args).label}`,
      rawInput: args?.path !== undefined ? { path: args.path } : undefined,
    }),
    presentResult: (_args, result) => {
      const diffs = result?.meta?.diffs
      if (!Array.isArray(diffs) || diffs.length === 0) return undefined
      return { card: 'diff', title: 'Uncommitted changes', diffs }
    },
    timeoutMs: 30_000,
    async execute(args, exec) {
      const cwd = exec?.agent?.session?.header?.cwd ?? process.cwd()
      const report = await collect(ctx, cwd, args ?? {}, exec?.signal)
      if (!report.ok) throw new Error(`dsh-diff: ${report.error}`)
      return {
        summary: toolText(report),
        patch: report.patch,
        files: report.files.map((file) => ({
          path: file.path,
          added: file.added,
          removed: file.removed,
          binary: file.binary,
        })),
        untracked: report.untracked,
      }
    },
  })

  ctx.commands.register({
    name: 'diff',
    description: 'обзор незакоммиченных изменений (структурная карточка через show_diff)',
    input: { hint: '[путь] [--staged] [--ref <ref>] [--patch]' },
    handler: async ({ rawInput, agent }) => {
      const parts = String(rawInput ?? '').trim().split(/\s+/).filter((part) => part !== '')
      const args = {}
      let wantPatch = false
      let path
      for (let i = 0; i < parts.length; i += 1) {
        const part = parts[i]
        if (part === '--staged' || part === '--cached') args.staged = true
        else if (part === '--patch' || part === '-p') wantPatch = true
        else if (part === '--ref') {
          const ref = parts[i + 1]
          if (ref === undefined) return { kind: 'error', text: 'usage: /diff [путь] [--staged] [--ref <ref>] [--patch]' }
          args.ref = ref
          i += 1
        } else if (part.startsWith('-')) {
          return { kind: 'error', text: `неизвестный флаг: ${part}\nusage: /diff [путь] [--staged] [--ref <ref>] [--patch]` }
        } else path = part
      }
      if (path !== undefined) args.path = path

      const cwd = agent?.session?.header?.cwd ?? process.cwd()
      let report
      try {
        report = await collect(ctx, cwd, args)
      } catch (error) {
        return { kind: 'error', text: `dsh-diff: ${error instanceof Error ? error.message : String(error)}` }
      }
      if (!report.ok) return { kind: 'error', text: `dsh-diff: ${report.error}` }

      const lines = [toolText(report)]
      if (wantPatch && report.patch !== '') {
        lines.push('', report.patch.trimEnd())
      } else if (report.files.length > 0) {
        lines.push('', 'полный патч: /diff --patch; структурная карточка: попросите агента вызвать ' + TOOL_NAME)
      }
      return { kind: 'success', text: lines.join('\n') }
    },
  })
}
