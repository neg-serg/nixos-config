/**
 * Smoke tests for the anchor classifier in tool-bootstrap.mjs.
 * Run: node tool-bootstrap.test.mjs
 * Asserts the thinking-mode discipline classification used by the neg preset's
 * promotion gate (structural stage markers vs. first-person/filler markers).
 */

import assert from 'node:assert/strict'
import { classifyReasoning, hasAnchoredReasoning } from './tool-bootstrap.mjs'

function check(text, expectedLabel) {
  const actual = classifyReasoning(text)
  assert.equal(actual.label, expectedLabel, `"${text}" -> expected ${expectedLabel}, got ${actual.label}`)
}

// disciplined: structural chain, no first-person/filler
check('анализ ограничений → выбор инструмента → план действий → исполнение', 'disciplined')
check('проверяю шаги и вызываю инструмент', 'disciplined')
check('ограничения: нет доступа. инструмент: read. план: прочитать файл.', 'disciplined')
check('ограничения -> инструмент -> план -> исполнение', 'disciplined')

// undisciplined: first-person / filler markers
check('Я думаю, надо проверить ещё раз...', 'undisciplined')
check('(надо подумать) → инструмент', 'undisciplined')
check('we should check the plan', 'undisciplined')
check('мне кажется, стоит попробовать', 'undisciplined')

// ambiguous: empty / no markers
check('', 'ambiguous')
check('просто текст без маркеров', 'ambiguous')

// hasAnchoredReasoning: first reasoning block decides; non-array is false
assert.equal(hasAnchoredReasoning(null), false)
assert.equal(hasAnchoredReasoning([{ type: 'reasoning', text: 'анализ ограничений → план' }]), true)
assert.equal(hasAnchoredReasoning([{ type: 'reasoning', text: 'я думаю надо' }, { type: 'reasoning', text: 'ограничения → план' }]), false)
assert.equal(hasAnchoredReasoning([{ type: 'text', text: 'hello' }]), false)

console.log('tool-bootstrap classifier tests OK')
