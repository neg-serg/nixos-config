/**
 * dsh-mode: slash commands for the dsh web GUI —
 *   /mode  — list the available agent presets (modes) or switch the default one;
 *   /fast  — switch the default to the lean `fast` preset and set model
 *            reasoning effort to `low` (thinks less, fewer tokens);
 *   /smart — switch back to the full `neg` preset with `high` reasoning effort;
 *   /effort — show or set the default model reasoning effort
 *             (off | low | high | max | auto — auto clears the saved level back
 *             to the adapter default).
 *
 * The defaults live in the `agent-presets` and `agent-default-model` settings
 * namespaces (~/.dsh/settings.yaml). The settings document is hot-reloaded,
 * so a change applies to the next created session without a dsh restart;
 * running sessions keep the preset they were composed from (a session's
 * preset is fixed once it has started).
 */

/** Cordis plugin name — must match the patch row / package name. */
export const name = 'dsh-mode'

/** Required services: slash-command registry, settings store, preset roster, default model. */
export const inject = ['commands', 'settings', 'agentPresets', 'agentDefaultModel']

/**
 * Settings namespace the agent-presets service registers. dsh 0.1.5-rc.1
 * dropped the `settingsNamespace()` helper (and @deepseek-ai/dsh-settings'
 * other exports besides the service class): a namespace is now the bare
 * string, and section registration goes through ctx.settings.installSection.
 */
const SETTINGS_NS = 'agent-presets'

/** One line per preset; marks the current default and broken presets. */
function renderPresets(presets, current) {
  const lines = presets
    .toSorted((a, b) => (a.order ?? Number.POSITIVE_INFINITY) - (b.order ?? Number.POSITIVE_INFINITY) || a.id.localeCompare(b.id))
    .map((p) => {
      const mark = p.broken !== undefined ? '✗' : p.id === current ? '*' : ' '
      const name = p.name !== undefined ? ` — ${p.name}` : ''
      const broken = p.broken !== undefined ? ' (broken)' : ''
      return `${mark} ${p.id}${name}${broken}`
    })
  return lines.join('\n')
}

/** Human-readable listing of what the user can pick. */
function listText(presets, current) {
  const currentText = current !== undefined ? current : '(не задан)'
  return `режим по умолчанию: ${currentText}\n\nдоступно:\n${renderPresets(presets, current)}\n\nсменить: /mode <id> | /fast | /smart`
}

/** Switch the default preset and the model reasoning effort in one step. */
async function setFastDefault(ctx, presetId, effort, effortLabel) {
  const presets = await ctx.agentPresets.list()
  const target = presets.find((p) => p.id === presetId && p.broken === undefined)
  if (target === undefined) {
    const current = ctx.settings.get(SETTINGS_NS)?.default
    return { kind: 'error', text: `нет пресета «${presetId}».\n\n${listText(presets, current)}` }
  }
  await ctx.settings.update(SETTINGS_NS, { default: presetId })
  const model = ctx.agentDefaultModel.currentSelection()
  await ctx.agentDefaultModel.saveSelection({
    provider: model.provider,
    model: model.model,
    reasoningEffort: effort,
  })
  const name = target.name !== undefined ? ` (${target.name})` : ''
  return {
    kind: 'success',
    text: `режим по умолчанию → ${presetId}${name}; мышление → ${effortLabel}. Применится к новым сессиям; текущая сессия остаётся на своём пресете.`,
  }
}

export function apply(ctx) {
  ctx.commands.register({
    name: 'mode',
    description: 'агент-пресет: список режимов или смена режима по умолчанию',
    input: { hint: '[id]' },
    handler: async ({ rawInput }) => {
      const id = rawInput.trim()
      const current = ctx.settings.get(SETTINGS_NS)?.default
      const presets = await ctx.agentPresets.list()
      if (id === '') {
        return { kind: 'success', text: listText(presets, current) }
      }
      const target = presets.find((p) => p.id === id && p.broken === undefined)
      if (target === undefined) {
        return { kind: 'error', text: `нет пресета «${id}».\n\n${listText(presets, current)}` }
      }
      await ctx.settings.update(SETTINGS_NS, { default: id })
      const note = target.name !== undefined ? ` (${target.name})` : ''
      return {
        kind: 'success',
        text: `режим по умолчанию → ${id}${note}. Применится к новым сессиям; текущая сессия остаётся на своём пресете.`,
      }
    },
  })

  ctx.commands.register({
    name: 'fast',
    description: 'режим по умолчанию → fast (лёгкий, мало токенов) + мышление low',
    handler: async () => setFastDefault(ctx, 'fast', 'low', 'low'),
  })

  ctx.commands.register({
    name: 'smart',
    description: 'режим по умолчанию → neg (полный) + мышление high',
    handler: async () => setFastDefault(ctx, 'neg', 'high', 'high'),
  })

  // Effort levels the DeepSeek adapter accepts; medium/xhigh are not offered
  // because the DeepSeek API maps both to `high` on the wire.
  const EFFORT_LEVELS = ['off', 'low', 'high', 'max']

  ctx.commands.register({
    name: 'effort',
    description: 'уровень мышления модели по умолчанию: /effort off|low|high|max|auto',
    input: { hint: '[off|low|high|max|auto]' },
    handler: async ({ rawInput }) => {
      const model = ctx.agentDefaultModel.currentSelection()
      const arg = rawInput.trim()
      if (arg === '') {
        const current = model.reasoningEffort ?? '(auto — дефолт адаптера)'
        return {
          kind: 'success',
          text:
            `текущая модель: ${model.provider}/${model.model}\n` +
            `effort по умолчанию: ${current}\n\n` +
            `сменить: /effort ${EFFORT_LEVELS.join(' | ')} | auto\n` +
            '(на DeepSeek medium и xhigh эквивалентны high, поэтому не предлагаются)',
        }
      }
      if (arg === 'auto') {
        await ctx.agentDefaultModel.saveSelection({ provider: model.provider, model: model.model })
        return {
          kind: 'success',
          text: 'effort → auto: новые сессии получат дефолт адаптера (DeepSeek: high).',
        }
      }
      if (!EFFORT_LEVELS.includes(arg)) {
        return {
          kind: 'error',
          text: `неизвестный effort «${arg}»: доступно ${EFFORT_LEVELS.join(' | ')} | auto.`,
        }
      }
      await ctx.agentDefaultModel.saveSelection({
        provider: model.provider,
        model: model.model,
        reasoningEffort: arg,
      })
      return {
        kind: 'success',
        text: `effort по умолчанию → ${arg}. Применится к новым сессиям; текущая не переключается на лету.`,
      }
    },
  })
}
