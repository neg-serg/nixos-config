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
  const currentText = current !== undefined ? current : '(not set)'
  return `default mode: ${currentText}\n\navailable:\n${renderPresets(presets, current)}\n\nswitch: /mode <id> | /fast | /smart`
}

/** Switch the default preset and the model reasoning effort in one step. */
async function setFastDefault(ctx, presetId, effort, effortLabel) {
  const presets = await ctx.agentPresets.list()
  const target = presets.find((p) => p.id === presetId && p.broken === undefined)
  if (target === undefined) {
    const current = ctx.settings.get(SETTINGS_NS)?.default
    return { kind: 'error', text: `no preset «${presetId}».\n\n${listText(presets, current)}` }
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
    text: `default mode → ${presetId}${name}; thinking → ${effortLabel}. Applies to new sessions; the current session keeps its preset.`,
  }
}

export function apply(ctx) {
  ctx.commands.register({
    name: 'mode',
    description: 'agent preset: list modes or switch the default mode',
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
        return { kind: 'error', text: `no preset «${id}».\n\n${listText(presets, current)}` }
      }
      await ctx.settings.update(SETTINGS_NS, { default: id })
      const note = target.name !== undefined ? ` (${target.name})` : ''
      return {
        kind: 'success',
        text: `default mode → ${id}${note}. Applies to new sessions; the current session keeps its preset.`,
      }
    },
  })

  ctx.commands.register({
    name: 'fast',
    description: 'default mode → fast (light, few tokens) + thinking low',
    handler: async () => setFastDefault(ctx, 'fast', 'low', 'low'),
  })

  ctx.commands.register({
    name: 'smart',
    description: 'default mode → neg (full) + thinking high',
    handler: async () => setFastDefault(ctx, 'neg', 'high', 'high'),
  })

  // Effort levels the DeepSeek adapter accepts; medium/xhigh are not offered
  // because the DeepSeek API maps both to `high` on the wire.
  const EFFORT_LEVELS = ['off', 'low', 'high', 'max']

  ctx.commands.register({
    name: 'effort',
    description: 'default model reasoning effort: /effort off|low|high|max|auto',
    input: { hint: '[off|low|high|max|auto]' },
    handler: async ({ rawInput }) => {
      const model = ctx.agentDefaultModel.currentSelection()
      const arg = rawInput.trim()
      if (arg === '') {
        const current = model.reasoningEffort ?? '(auto — adapter default)'
        return {
          kind: 'success',
          text:
            `current model: ${model.provider}/${model.model}\n` +
            `default effort: ${current}\n\n` +
            `switch: /effort ${EFFORT_LEVELS.join(' | ')} | auto\n` +
            '(on DeepSeek, medium and xhigh are equivalent to high, so they are not offered)',
        }
      }
      if (arg === 'auto') {
        await ctx.agentDefaultModel.saveSelection({ provider: model.provider, model: model.model })
        return {
          kind: 'success',
          text: 'effort → auto: new sessions get the adapter default (DeepSeek: high).',
        }
      }
      if (!EFFORT_LEVELS.includes(arg)) {
        return {
          kind: 'error',
          text: `unknown effort «${arg}»: available ${EFFORT_LEVELS.join(' | ')} | auto.`,
        }
      }
      await ctx.agentDefaultModel.saveSelection({
        provider: model.provider,
        model: model.model,
        reasoningEffort: arg,
      })
      return {
        kind: 'success',
        text: `default effort → ${arg}. Applies to new sessions; the current one does not switch on the fly.`,
      }
    },
  })
}
