/**
 * dsh-rules-injector: inject repository rules (rules/*.md + root AGENTS.md)
 * as additional context when the model touches matching files.
 *
 * Ported from oh-my-opencode rules-injector (see
 * /etc/nixos/docs/howto/designs/rules-hooks.md section 1). Delivery rides the
 * post-execute decision's additionalContexts (source {kind:'plugin'}), same
 * mechanism as repeat-tool-reminder: advisory, never blocks or rewrites calls.
 *
 * Rule semantics (YAML frontmatter):
 *   - no frontmatter          -> always apply
 *   - alwaysApply: true       -> always apply
 *   - glob: <pattern>         -> apply when the touched file matches
 *   - frontmatter, no glob    -> does NOT apply (explicitly scoped rule)
 * glob supports '*' (one path segment) and '**' (any depth).
 */

import { readdirSync, readFileSync } from 'node:fs'
import { join, relative, basename, sep } from 'node:path'
import { createUserMessage } from '@deepseek-ai/dsh-llm'

export const name = 'dsh-rules-injector'

const DEFAULT_RULES_DIR = 'rules'
const TOUCH_TOOLS = new Set(['read', 'write', 'edit', 'str_replace_editor'])

/** Minimal YAML-frontmatter parser: returns { alwaysApply, glob }. */
function parseFrontmatter(text) {
  if (!text.startsWith('---')) return { alwaysApply: true, glob: null }
  const end = text.indexOf('\n---', 3)
  if (end === -1) return { alwaysApply: true, glob: null }
  const fm = text.slice(3, end)
  let alwaysApply = false
  let glob = null
  for (const rawLine of fm.split('\n')) {
    const line = rawLine.trim()
    const lower = line.toLowerCase()
    if (lower.startsWith('alwaysapply:')) {
      alwaysApply = line.slice(line.indexOf(':') + 1).trim().toLowerCase() === 'true'
    } else if (line.startsWith('glob:')) {
      glob = line.slice(5).trim()
    }
  }
  return { alwaysApply, glob }
}

/** Convert a glob to a RegExp source: '*' -> one segment, '**' -> any depth. */
function globToRegExp(glob) {
  let rx = ''
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i]
    if (c === '*') {
      if (glob[i + 1] === '*') {
        rx += '.*'
        i += 1
      } else {
        rx += '[^/]*'
      }
    } else if ('+^$' + '{}()|[]' + '.\\'.includes(c) || c === '\\') {
      rx += '\\' + c
    } else {
      rx += c
    }
  }
  return new RegExp('^' + rx + '$')
}

/** A rule file itself is never injected (avoids recursion/noise). */
function isRuleFile(p) {
  if (basename(p) === 'AGENTS.md') return true
  return p.split(sep).includes('rules')
}

export function apply(ctx, config = {}) {
  const rulesDir = config.rulesDir ?? DEFAULT_RULES_DIR
  /** sessionID -> Set(rulePath) — already-injected rules per session. */
  const cache = new Map()

  function workspaceRoot(exec) {
    return (
      exec?.agent?.session?.header?.cwd ??
      (typeof ctx.workspace === 'string' ? ctx.workspace : undefined) ??
      process.cwd()
    )
  }

  /** Candidate rule files under root: <root>/AGENTS.md + <root>/<rulesDir>/*.md. */
  function scanRules(root) {
    const out = []
    try {
      readFileSync(join(root, 'AGENTS.md'), 'utf8')
      out.push(join(root, 'AGENTS.md'))
    } catch { /* no root AGENTS.md */ }
    try {
      for (const entry of readdirSync(join(root, rulesDir), { withFileTypes: true })) {
        if (entry.isFile() && entry.name.endsWith('.md')) {
          out.push(join(root, rulesDir, entry.name))
        }
      }
    } catch { /* no rules dir */ }
    return out
  }

  function matches(rulePath, rel) {
    try {
      const fm = parseFrontmatter(readFileSync(rulePath, 'utf8'))
      if (fm.alwaysApply) return true
      if (fm.glob) return globToRegExp(fm.glob).test(rel)
      return false
    } catch {
      return false
    }
  }

  ctx.on('tools/post-execute', async (exec, result, next) => {
    const downstream = await next()
    if (!TOUCH_TOOLS.has(exec.name)) return downstream

    const filePath = result?.value?.path ?? exec.arguments?.file_path
    if (!filePath || isRuleFile(filePath)) return downstream

    const sessionID = exec.agent?.session?.id
    if (!sessionID) return downstream

    const root = workspaceRoot(exec)
    let rel = filePath
    try {
      rel = relative(root, filePath)
    } catch { /* keep absolute as fallback */ }

    let seen = cache.get(sessionID)
    if (!seen) {
      seen = new Set()
      cache.set(sessionID, seen)
    }

    const additions = []
    for (const rulePath of scanRules(root)) {
      if (seen.has(rulePath)) continue
      if (!matches(rulePath, rel)) continue
      seen.add(rulePath)
      try {
        // additionalContexts are MESSAGES: they enter the inbox and are appended
        // as user/message, so they need role/content (a bare {source, text}
        // shape yields content: null and crashes the LLM serializer).
        additions.push(createUserMessage({
          content: [{ type: 'text', text: readFileSync(rulePath, 'utf8') }],
          source: { kind: 'plugin', plugin: 'rules-injector', form: 'instructions' },
        }))
      } catch { /* unreadable rule — skip */ }
    }
    if (additions.length === 0) return downstream

    return {
      ...downstream,
      additionalContexts: [...(downstream.additionalContexts ?? []), ...additions],
    }
  })

  // Fresh session / compaction: clear the per-session injection cache.
  ctx.on('session/event', (session, event) => {
    if (event.type === 'compaction/start' || event.type === 'session/end-seed') {
      cache.delete(session.id)
    }
  })
}
