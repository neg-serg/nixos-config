/**
 * dsh-model-hotkeys: Ctrl+Alt+<digit> switches the live model.
 *
 * The shortcut seam (`ctx.tuiShortcuts`) is public. The live channel is not:
 * the TUI keeps it in a host-internal WeakMap, so this plugin loads the
 * registry lazily from the installed bundle. The import is deliberately
 * dynamic and pre-warmed with a catch: if a TUI upgrade moves the internal
 * path (or the harness stops resolving `@deepseek-ai/cordis` for it), the
 * hotkeys go dead but the TUI still boots. After an upgrade check that
 * `<pkg>/lib/types/adapter/channel/host-registry.js` exists and that the
 * channel still exposes `listModels()` / `switchModel()`.
 *
 * Routes are resolved by model id, so the local `llama-swap` provider and
 * `deepseek-official` both work without hardcoding a provider id.
 */

/** The only unsupported dependency: the host-internal Channel registry. */
const REGISTRY =
  '../../@deepseek-harness-tui/dsh-tui/lib/types/adapter/channel/host-registry.js'

/** Cordis plugin name — must match the patch row / package name. */
export const name = 'dsh-model-hotkeys'

/** The TUI mounts the shortcut registry; without it the plugin has no seam. */
export const inject = ['tuiShortcuts']

/** [digit, model id shown in /model, label used by shortcut list()] */
export const ROUTES = [
  ['0', 'deepseek-flash', 'DeepSeek V4.1 Flash'],
  ['1', 'qwen3.6-35b-abliterated', 'Qwen3.6-35B (local)'],
  ['2', 'qwen3.8-27b-abliterated', 'Qwen3.8-27B (local)'],
  ['4', 'gemma4-26b-abliterated', 'Gemma 4 26B (local)'],
  ['5', 'qwen3-vl-8b-abliterated', 'Qwen3-VL-8B (local)'],
  ['6', 'tiny', 'Spark 4B (CPU)'],
]

let registryPromise

/** Load the internal registry once; callers catch, so a miss is not fatal. */
export function loadRegistry() {
  registryPromise ??= import(REGISTRY)
  return registryPromise
}

/**
 * Resolve the model id across every provider and switch to it.
 * Exported so a unit test can exercise it without the TUI.
 */
export async function switchToModel(channel, modelId) {
  if (channel === undefined || typeof channel.listModels !== 'function') return false
  const models = await channel.listModels()
  const hit = models.find((model) => model.id === modelId)
  if (hit === undefined) return false
  return channel.switchModel(hit.provider, hit.id)
}

/** Fire-and-forget pre-warm so a broken internal path shows up in the log. */
function prewarm() {
  loadRegistry().catch((error) => {
    console.warn(`[dsh-model-hotkeys] channel registry unavailable: ${error.message}`)
  })
}

export function apply(ctx) {
  prewarm()
  for (const [digit, modelId, label] of ROUTES) {
    ctx.effect(() =>
      ctx.tuiShortcuts.register(
        `ctrl+alt+${digit}`,
        {
          description: `Model: ${label}`,
          handler: async () => {
            const { getRegisteredTuiChannel } = await loadRegistry()
            const channel = getRegisteredTuiChannel(ctx)
            await switchToModel(channel, modelId)
          },
        },
        ctx,
      ),
    )
  }
}
