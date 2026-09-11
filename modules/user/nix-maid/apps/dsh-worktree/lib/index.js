/**
 * dsh-worktree: the `/worktree` slash command.
 *
 * Wraps the `dsh-worktree` helper (packages/local-bin/bin/dsh-worktree, deployed
 * to ~/.local/bin) so a running session can spawn and manage the isolated
 * worktrees that parallel dsh sessions live in. The helper owns every policy
 * decision — where trees live, branch naming, the launcher — this plugin only
 * forwards argv and renders the result.
 *
 * Two seams matter here:
 *
 * 1. `ctx.subprocess`, never `node:child_process`: the harness runs its own
 *    spawners through this service (the plugin-vetting tripwire watches it), and
 *    it hands back collected output that stays readable after exit.
 * 2. The subprocess service deliberately scrubs `DSH_*` names out of the child
 *    environment (harness identity must not leak implicitly). DSH_WORKTREE_* is
 *    exactly such a name, so it is forwarded explicitly through the spec's
 *    `env`, which merges after the scrub. Without that, a tree created from
 *    inside a session would land in the default root while the shell's
 *    `dsh-worktree` used the configured one.
 */

/** Cordis plugin name — must match the patch row / package name. */
export const name = 'dsh-worktree'

/** Required services: the slash-command registry and the subprocess seam. */
export const inject = ['commands', 'subprocess']

/** Collected-output cap per stream; the helper is chatty on stderr, not on stdout. */
const MAX_BYTES = 64 * 1024

/** Post-create hooks can legitimately install dependencies; allow a slow one. */
const TIMEOUT_MS = 120_000

/** Environment that must survive the subprocess env scrub (see module doc). */
const FORWARDED_ENV = ['DSH_WORKTREE_ROOT', 'DSH_WORKTREE_CMD', 'DSH_WORKTREE_POST_CREATE']

const VERBS = ['new', 'list', 'path', 'rm', 'prune']

const USAGE =
  'usage: /worktree new <name> [--from REF] [--open auto|kitty|zellij|print] [--copy RELPATH] ' +
  '| /worktree list | /worktree path <name> | /worktree rm <name> [--force] | /worktree prune'

/** Only the helper's own verbs are accepted, so a typo cannot run something else. */
function parseArgs(rawInput) {
  const text = String(rawInput ?? '').trim()
  if (text === '') return ['list']
  const argv = text.split(/\s+/)
  if (!VERBS.includes(argv[0])) return null
  return argv
}

function forwardedEnv(env) {
  const out = {}
  for (const key of FORWARDED_ENV) {
    const value = env[key]
    if (value !== undefined && value !== '') out[key] = value
  }
  return out
}

function render(stdout, stderr) {
  return [stdout.text, stderr.text]
    .map((part) => (part ?? '').trimEnd())
    .filter((part) => part !== '')
    .join('\n')
}

export function apply(ctx) {
  ctx.commands.register({
    name: 'worktree',
    description: 'изолированные git-worktree для параллельных сессий (dsh-worktree)',
    input: { hint: 'new <имя> | list | path <имя> | rm <имя> | prune' },
    handler: async ({ rawInput, agent }) => {
      const argv = parseArgs(rawInput)
      if (argv === null) return { kind: 'error', text: USAGE }

      const cwd = agent?.session?.header?.cwd ?? process.cwd()

      // Prefer the provider's own lookup; fall back to a bare name so a provider
      // without resolveExecutable still gets its normal PATH resolution.
      let bin = 'dsh-worktree'
      if (typeof ctx.subprocess.resolveExecutable === 'function') {
        try {
          bin = await ctx.subprocess.resolveExecutable('dsh-worktree')
        } catch {
          /* fall through to the PATH lookup in spawn */
        }
      }

      let handle
      try {
        handle = ctx.subprocess.spawn({
          argv: [bin, ...argv],
          cwd,
          stdio: {
            stdin: 'ignore',
            stdout: { maxBytes: MAX_BYTES },
            stderr: { maxBytes: MAX_BYTES },
          },
          graceMs: 5000,
          env: forwardedEnv(process.env),
          signal: AbortSignal.timeout(TIMEOUT_MS),
        })
      } catch (error) {
        return {
          kind: 'error',
          text:
            `не удалось запустить dsh-worktree: ${error instanceof Error ? error.message : String(error)}\n` +
            'проверьте, что ~/.local/bin в PATH (пакет packages/local-bin) и что сборка прокатана',
        }
      }

      let outcome
      try {
        outcome = await handle.done
      } catch (error) {
        return {
          kind: 'error',
          text: `dsh-worktree не сообщил результат (таймаут ${TIMEOUT_MS / 1000}s или сбой провайдера): ${
            error instanceof Error ? error.message : String(error)
          }`,
        }
      }

      const stdout = handle.collected.stdout?.readFrom(0) ?? { text: '' }
      const stderr = handle.collected.stderr?.readFrom(0) ?? { text: '' }
      const text = render(stdout, stderr)

      if (outcome.signal !== null || outcome.exitCode === null) {
        return { kind: 'error', text: `dsh-worktree убит сигналом ${outcome.signal ?? '(неизвестно)'}\n${text}` }
      }
      if (outcome.exitCode === 0) {
        return { kind: 'success', text: text === '' ? 'готово' : text }
      }
      return {
        kind: 'error',
        text: text === '' ? `dsh-worktree exited with ${outcome.exitCode}` : text,
      }
    },
  })
}
