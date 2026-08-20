/**
 * dsh-plan-format-validator: gate exit_plan_mode plans on shape.
 *
 * Harness hook from oh-my-opencode backlog ("plan-format-validator"): before
 * an exit_plan_mode plan is presented for user review, check it has the
 * minimum decision-complete shape (plan-before-code.md / ulw-plan):
 *   1. starts with a markdown heading (# …),
 *   2. has at least one section heading (## …) — e.g. Goal / Steps / Risks,
 *   3. has a non-empty body beyond the headings.
 * A malformed plan is denied with a reason naming what is missing, so the
 * agent revises before the user sees it. Strictness is deliberately low: the
 * gate checks shape, not content quality (Momus QA stays in the workflow).
 *
 * Mechanism: tools/pre-execute deny on the exit_plan_mode tool when
 * args.plan fails the checks. Never touches other tools.
 */

export const name = 'dsh-plan-format-validator'
export const inject = []

const PLAN_TOOL = 'exit_plan_mode'
const HASH = String.fromCharCode(35) // '#'

function headingLines(plan) {
  const lines = String(plan ?? '').split(/\r?\n/)
  let h1 = null
  let sections = 0
  let bodyChars = 0
  for (const line of lines) {
    if (/^#\s+\S/.test(line)) h1 = line.replace(/^#\s+/, '').trim()
    else if (/^##\s+\S/.test(line)) sections += 1
    else if (/^###\s+\S/.test(line)) sections += 1
    else bodyChars += line.trim().length
  }
  return { h1, sections, bodyChars }
}

export function apply(ctx) {
  ctx.on('tools/pre-execute', async (exec, next) => {
    const decision = await next()
    if (decision.kind !== 'allow') return decision
    if (exec.name !== PLAN_TOOL) return decision
    const plan = exec?.args?.plan ?? ''
    if (typeof plan !== 'string' || plan.trim() === '') {
      return { kind: 'deny', reason: 'plan-format-validator: план пуст — отправь полный markdown-план (начинается с "' + HASH + ' ").' }
    }
    const { h1, sections, bodyChars } = headingLines(plan)
    const missing = []
    if (h1 === null) missing.push('заголовок "' + HASH + ' …"')
    if (sections === 0) missing.push('секции "## …" (например ## Цель / ## Шаги / ## Риски)')
    if (bodyChars < 40) missing.push('непустое тело плана')
    if (missing.length === 0) return decision
    return {
      kind: 'deny',
      reason: 'plan-format-validator: план неполный — добавь: ' + missing.join(', ') + '. Исправь и отправь exit_plan_mode снова.',
    }
  })
}
