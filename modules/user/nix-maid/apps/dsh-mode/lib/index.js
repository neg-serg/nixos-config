import { settingsNamespace } from '@deepseek-ai/dsh-settings'

/**
 * dsh-mode: slash command `/mode` for the dsh web GUI — list the available
 * agent presets (modes) or switch the default one for NEW sessions.
 *
 * The default lives in the `agent-presets` settings namespace
 * (`agent-presets.default` in ~/.dsh/settings.yaml). The settings document is
 * hot-reloaded, so a change applies to the next created session without a
 * dsh restart; running sessions keep the preset they were composed from.
 */

/** Cordis plugin name — must match the patch row / package name. */
export const name = 'dsh-mode'

/** Required services: slash-command registry, settings store, preset roster. */
export const inject = ['commands', 'settings', 'agentPresets']

/** Settings namespace the agent-presets service registers. */
const SETTINGS_NS = settingsNamespace('agent-presets')

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
  return `режим по умолчанию: ${currentText}\n\nдоступно:\n${renderPresets(presets, current)}\n\nсменить: /mode <id>`
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
}
