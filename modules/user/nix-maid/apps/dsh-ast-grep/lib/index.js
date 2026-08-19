/**
 * dsh-ast-grep: structural code search and rewrite via the ast-grep binary
 * (sg, from nixpkgs). Use when syntax shape matters more than text.
 *
 * Ported from omp's ast_grep tool (plan: docs/howto/agent-deferred.ru.md §5).
 * Ops: search (pattern + optional lang/glob/path, JSON output) and rewrite
 * (pattern -> rewrite; apply:false previews the match count, default applies
 * with -U update-all). One language per call; $NAME captures are ast-grep's.
 */

import { spawn } from 'node:child_process'
import { existsSync } from 'node:fs'
import { defineTool } from '@deepseek-ai/dsh-tools'

export const name = 'dsh-ast-grep'
export const inject = ['tools']

/**
 * Resolve the ast-grep binary. Use the canonical name 'ast-grep' (the 'sg'
 * alias collides with shadow-utils' sg = switch group on this host).
 */
function resolveSg() {
  const home = process.env.HOME || ''
  const candidates = [
    home + '/.local/bin/ast-grep',
    '/run/current-system/sw/bin/ast-grep',
    '/usr/local/bin/ast-grep',
  ]
  for (const p of candidates) {
    try { if (existsSync(p)) return p } catch (e) { /* keep probing */ }
  }
  return 'ast-grep'
}

function runSg(args, timeoutMs) {
  return new Promise(function (resolve, reject) {
    const proc = spawn(resolveSg(), args, { stdio: ['pipe', 'pipe', 'pipe'] })
    let out = ''
    let errOut = ''
    proc.stdout.on('data', function (d) { out += String(d) })
    proc.stderr.on('data', function (d) { errOut += String(d) })
    const timer = setTimeout(function () {
      try { proc.kill('SIGKILL') } catch (e) { /* ignore */ }
      reject(new Error('ast-grep timed out'))
    }, timeoutMs || 60000)
    proc.on('error', function (e) { clearTimeout(timer); reject(e) })
    proc.on('exit', function (code) { clearTimeout(timer); resolve({ code: code, out: out, err: errOut }) })
  })
}

function buildArgs(params, extra) {
  const args = extra.slice()
  if (params.lang) args.push('-l', String(params.lang))
  if (params.glob) args.push('-g', String(params.glob))
  if (params.path) args.push(String(params.path))
  return args
}

function astGrepTool() {
  return defineTool({
    name: 'ast_grep',
    description: 'Structural code search/rewrite via ast-grep. Use when syntax shape matters (calls, ' +
      'declarations). Ops: search (pattern, optional lang/glob/path), rewrite (pattern -> rewrite; ' +
      'apply:false previews match count). $NAME captures one node; $$$NAME zero-or-more.',
    parameters: {
      op: { type: 'string', required: true, description: 'search | rewrite' },
      pattern: { type: 'string', required: true, description: 'AST pattern (e.g. console.log($A)).' },
      rewrite: { type: 'string', description: 'Replacement for rewrite (metavariables allowed).' },
      lang: { type: 'string', description: 'Language (rust, c, cpp, python, typescript, ...).' },
      glob: { type: 'string', description: 'File glob filter (e.g. **/*.rs).' },
      path: { type: 'string', description: 'Root path to search (default current dir).' },
      apply: { type: 'boolean', description: 'rewrite: apply changes (default true); false = preview.' },
    },
    output: {
      schema: { type: 'object', additionalProperties: true },
      render: function (_a, v) {
        return [{ type: 'text', text: JSON.stringify(v, null, 2) }]
      },
    },
    isConcurrencySafe: function () { return false },
    timeoutMs: 90000,
    async execute(args, exec) {
      const pattern = String(args.pattern)
      if (args.op === 'search') {
        const sgArgs = buildArgs(args, ['-p', pattern, '--json'])
        const res = await runSg(sgArgs, args.timeout)
        let matches = []
        try { matches = JSON.parse(res.out) } catch (e) { matches = [] }
        if (res.code !== 0 && matches.length === 0) {
          return { ok: false, error: (res.err || res.out).slice(0, 500), exitCode: res.code }
        }
        return {
          ok: true,
          count: matches.length,
          matches: matches.slice(0, 200).map(function (m) {
            const start = m.range && m.range.start || {}
            return {
              file: m.file || '',
              line: (start.line !== undefined ? start.line : 0) + 1,
              column: (start.column !== undefined ? start.column : 0) + 1,
              text: String(m.text || '').slice(0, 200),
            }
          }),
        }
      }
      if (args.op === 'rewrite') {
        if (!args.rewrite) throw new Error('ast_grep: rewrite needs rewrite')
        const preview = args.apply === false
        if (preview) {
          const sgArgs = buildArgs(args, ['-p', pattern, '--json'])
          const res = await runSg(sgArgs, args.timeout)
          let matches = []
          try { matches = JSON.parse(res.out) } catch (e) { matches = [] }
          return { ok: true, preview: true, count: matches.length,
            sample: matches.slice(0, 5).map(function (m) {
              const start = m.range && m.range.start || {}
              return (m.file || '') + ':' + ((start.line !== undefined ? start.line : 0) + 1)
            }) }
        }
        const sgArgs = buildArgs(args, ['run', '-p', pattern, '-r', String(args.rewrite), '-U'])
        const res = await runSg(sgArgs, args.timeout)
        return { ok: res.code === 0, output: (res.out || res.err).slice(0, 800), exitCode: res.code }
      }
      throw new Error('ast_grep: unknown op ' + args.op)
    },
  })
}

export function apply(ctx) {
  ctx.tools.register(astGrepTool())
}
