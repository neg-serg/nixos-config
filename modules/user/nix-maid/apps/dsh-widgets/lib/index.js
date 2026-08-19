/**
 * dsh-widgets, host half.
 *
 * Registers the general-purpose `json` tool on `ctx.tools`: the model passes a
 * raw JSON string and the tool validates it and projects a `{ kind: 'json-tree',
 * value, … }` presentationMeta descriptor that the browser half renders as a
 * collapsible, syntax-highlighted tree. No web route is needed — the tree is
 * pure React over persisted meta, unlike dsh-osm's Leaflet assets.
 *
 * The browser half (`lib/client.js`) also renders the tool's result AND adds
 * keyed toolviews for the agent-orchestration tools (subagent / workflow /
 * ralph / goal / jobs) that otherwise fall back to the generic tool card. A
 * client without it degrades to the tools' plain text results, so TUI and
 * headless surfaces keep working unchanged.
 *
 * The optional `bash_live` streaming tool (live terminal card in the chat)
 * is registered only when the `enableBashLive` deployment flag is set; it is
 * disabled by default.
 *
 * @module dsh-widgets
 */

import z from '@deepseek-ai/schemastery'
import { createWidgetTools } from './tools.js'

/** Cordis plugin name — must match the patch row / package name. */
export const name = 'dsh-widgets'

/** Required services: tool registry, the shell seam (for `bash_live`). */
export const inject = ['tools', 'shell']

/** Deployment configuration, validated by the Loader. */
export const Config = z.object({
  /** Hard cap on the raw JSON text argument (bytes). */
  maxInputBytes: z.natural().default(2_000_000),
  /** Cap on the persisted presentationMeta descriptor (bytes). */
  maxMetaBytes: z.natural().default(256_000),
  /**
   * Register the `bash_live` streaming tool. Off by default: it is buggy /
   * noisy in practice and needs `ctx.shell`; flip to true in the deployment
   * config to opt back in without touching the code.
   */
  enableBashLive: z.boolean().default(false),
})

/**
 * Register the widget tools.
 * @param ctx - registrant context.
 * @param config - validated deployment configuration.
 */
export function apply(ctx, config) {
  for (const tool of createWidgetTools(ctx, config)) {
    ctx.tools.register(tool)
  }
}

export { jsonMetaFrom } from './tools.js'
