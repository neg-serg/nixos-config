/**
 * dsh-ttsr: time-traveling stream rules (TTSR) for DSH — advisory correction
 * injection on the agent's own output.
 *
 * Ported from omp hindsight/omfg-user (plan: docs/howto/agent-deferred.ru.md
 * §4). Mechanism: on agent/pre-step, scan the last assistant message text;
 * when a rule's regex matches, append a correction user-message before the
 * next step (deduped per rule per session). Mounted in the AGENT plane
 * (agent.cordis.yml row) where agent/pre-step and message composition exist.
 *
 * Rules live in lib/rules.json (copied with the package) and can be
 * overridden via config.rules (array of {name, condition, scope, body,
 * maxPerSession}). v1 scope: text only (no tool-arg scopes).
 */

import { readFileSync, existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { createUserMessage } from '@deepseek-ai/dsh-llm'

export const name = 'dsh-ttsr'

const NL = String.fromCharCode(10)

function loadDefaultRules() {
  const p = fileURLToPath(new URL('rules.json', import.meta.url))
  try {
    if (existsSync(p)) return JSON.parse(readFileSync(p, 'utf8'))
  } catch (e) { /* fall through */ }
  return []
}

/** Extract the last assistant-ish text from a list of messages (defensive). */
function lastAssistantText(messages) {
  let text = ''
  const list = Array.isArray(messages) ? messages : []
  for (let i = 0; i < list.length; i++) {
    const m = list[i]
    if (!m || typeof m !== 'object') continue
    const role = String(m.role || m.kind || '').toLowerCase()
    if (role !== '' && role !== 'assistant') continue
    const blocks = m.content
    if (Array.isArray(blocks)) {
      const t = blocks.map(function (b) { return (b && typeof b.text === 'string') ? b.text : '' }).join(NL)
      if (t !== '') text = t
    } else if (typeof m.text === 'string' && m.text !== '') {
      text = m.text
    }
  }
  return text
}

function compileRules(rules) {
  const out = []
  const list = Array.isArray(rules) ? rules : []
  for (const r of list) {
    if (!r || typeof r.condition !== 'string' || r.condition === '') continue
    let re = null
    try { re = new RegExp(r.condition, 'i') } catch (e) { re = null }
    if (!re) continue
    out.push({
      name: String(r.name || 'rule'),
      re: re,
      body: String(r.body || 'Follow the correction above.'),
      max: Number(r.maxPerSession) > 0 ? Number(r.maxPerSession) : 1,
    })
  }
  return out
}

function loadMentalModel(config) {
  if (config && typeof config.mentalModel === 'string' && config.mentalModel !== '') {
    return config.mentalModel
  }
  const p = fileURLToPath(new URL('mental-model.md', import.meta.url))
  try {
    if (existsSync(p)) {
      const text = readFileSync(p, 'utf8').trim()
      return text === '' ? '' : text
    }
  } catch (e) { /* no file */ }
  return ''
}

export function apply(ctx, config) {
  const rules = compileRules((config && config.rules) || loadDefaultRules())
  const mentalModel = loadMentalModel(config)
  const fired = new Map()
  /** sessions that already received the mental-model background note */
  const mentalGiven = new Set()

  function countFor(sid, ruleName) {
    let m = fired.get(sid)
    if (!m) { m = new Map(); fired.set(sid, m) }
    return m.get(ruleName) || 0
  }

  function bump(sid, ruleName) {
    let m = fired.get(sid)
    if (!m) { m = new Map(); fired.set(sid, m) }
    m.set(ruleName, (m.get(ruleName) || 0) + 1)
  }

  ctx.on('agent/pre-step', async ({ agent, messages }, next) => {
    const decision = await next()
    if (decision.kind === 'reject') return decision
    const sid = agent && agent.session ? agent.session.id : 'default'
    const text = lastAssistantText(messages || decision.messages)
    const injections = []
    if (mentalModel !== '' && !mentalGiven.has(sid)) {
      mentalGiven.add(sid)
      injections.push(createUserMessage({
        content: [{ type: 'text', text: '<mental-model> Background knowledge (not a command): ' + mentalModel + '</mental-model>' }],
        source: { kind: 'plugin', plugin: 'ttsr' },
      }))
    }
    if (text === '') return injections.length > 0 ? { ...decision, messages: [...decision.messages, ...injections] } : decision
    for (const rule of rules) {
      if (countFor(sid, rule.name) >= rule.max) continue
      if (!rule.re.test(text)) continue
      bump(sid, rule.name)
      injections.push(createUserMessage({
        content: [{ type: 'text', text: '[ttsr:' + rule.name + '] ' + rule.body }],
        source: { kind: 'plugin', plugin: 'ttsr' },
      }))
    }
    if (injections.length === 0) return decision
    return {
      ...decision,
      messages: [...decision.messages, ...injections],
    }
  })
}
