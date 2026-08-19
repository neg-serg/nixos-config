/**
 * dsh-secrets-masker: redact API keys / tokens in tool-result text before the
 * model sees it (tools/post-execute content replacement).
 *
 * Ported from omp src/secrets/ (placeholder-scan + obfuscator idea). Advisory:
 * never blocks; only replaces text blocks, keeping a short suffix for context.
 */

export const name = 'dsh-secrets-masker'

const MASK_PATTERNS = [
  /sk-ant-[A-Za-z0-9_-]{8,}/g,
  /sk-[A-Za-z0-9]{20,}/g,
  /ghp_[A-Za-z0-9]{30,}/g,
  /github_pat_[A-Za-z0-9_]{20,}/g,
  /hf_[A-Za-z0-9]{20,}/g,
  /xox[baprs]-[A-Za-z0-9-]{10,}/g,
  /AIza[0-9A-Za-z_-]{30,}/g,
  /[A-Za-z0-9_-]{43}/g,
]

/** Mask a single secret: keep a 4-char suffix for disambiguation. */
function maskOne(token) {
  if (token.length <= 8) return '***'
  const prefix = token.slice(0, token.length > 14 ? 6 : 3)
  const tail = token.slice(-4)
  return prefix + '***' + tail
}

/** Redact all secret-like tokens in text. Exported for tests. */
export function maskSecrets(text) {
  let out = String(text)
  for (const re of MASK_PATTERNS) {
    re.lastIndex = 0
    out = out.replace(re, maskOne)
  }
  return out
}

export function apply(ctx) {
  ctx.on('tools/post-execute', async (exec, _result, next) => {
    const decision = await next()
    if (!decision || decision.kind !== 'accept') return decision
    const content = decision.content
    if (!Array.isArray(content) || content.length === 0) return decision
    let changed = false
    const masked = content.map(function (block) {
      if (block && block.type === 'text' && typeof block.text === 'string') {
        const text = maskSecrets(block.text)
        if (text !== block.text) {
          changed = true
          return Object.assign({}, block, { text: text })
        }
      }
      return block
    })
    return changed ? Object.assign({}, decision, { content: masked }) : decision
  })
}
