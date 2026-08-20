/**
 * dsh-desktop: Linux desktop control for DSH (backlog plan:
 * docs/howto/agent-backlog-research.ru.md §3).
 *
 * Layered backends (lib/backends.js):
 *   native — zero-daemon: hyprctl (windows/focus/move/resize), grim
 *            (screenshot), wtype (type/press_key). Light, short-lived.
 *   cul    — computer-use-linux MCP bridge: click/drag/scroll by pixels or
 *            semantic selectors, app state, set_value, perform_action.
 *            Spawned per call, killed after (no resident process).
 *   atspi  — accessibility tree via CUL (list_apps); needs org.a11y.Bus.
 *
 * Tool `desktop` actions (backend: auto | native | cul):
 *   doctor        readiness report across layers (JSON).
 *   windows       window list (native hyprctl; cul → list_windows).
 *   focused       active window (native hyprctl; cul → focused_window).
 *   screenshot    grim capture, full or window region; path for the
 *                 describe_image/read_image vision chain.
 *   focus         focus a window by address (native; cul → activate_window).
 *   move_window   move window frame (top-left desktop coords).
 *   resize_window resize window frame.
 *   type          type literal text (native wtype; cul → type_text).
 *   press_key     key/combo, e.g. ctrl+shift+t, super+Return.
 *   apps          AT-SPI app list (needs org.a11y.Bus).
 *   state         app accessibility state via CUL get_app_state.
 *   click/drag/scroll — CUL bridge (pixel or semantic selectors).
 *   set_value / perform_action — CUL accessibility actions.
 *
 * Resource policy: "auto" keeps everything native where possible; CUL is
 * spawned only for actions native cannot do, one process per call, killed
 * in finally. No daemons are started by this plugin.
 *
 * Config: { culBin? } — binary path override (default resolves
 * ~/.local/bin → /run/current-system/sw/bin → PATH).
 */

import { defineTool } from '@deepseek-ai/dsh-tools'
import {
  nativeDoctor, nativeWindows, nativeFocused, nativeScreenshot,
  nativeFocus, nativeMoveWindow, nativeResizeWindow, nativeType, nativePressKey,
  CulMCP, culDoctor, atspiApps,
} from './backends.js'

/** Cordis plugin name — must match the patch row / package name. */
export const name = 'dsh-desktop'

/** Required service: the tool registry. */
export const inject = ['tools']

const resolveCul = (config) => config?.culBin ?? '/home/neg/.local/bin/computer-use-linux'

const culOnly = new Set([
  'click', 'drag', 'scroll', 'state', 'set_value', 'perform_action',
])

const runCul = async (culBin, action, args) => {
  const mcp = new CulMCP(culBin)
  try {
    await mcp.start()
    const params = {}
    if (action === 'click') {
      if (args.x !== undefined && args.y !== undefined) Object.assign(params, { x: Number(args.x), y: Number(args.y) })
      else if (args.selector) Object.assign(params, { name: String(args.selector) })
      else if (args.index !== undefined) Object.assign(params, { index: Number(args.index) })
      else throw new Error('desktop click needs x+y, selector, or index')
    } else if (action === 'drag') {
      if (args.from_x === undefined || args.from_y === undefined || args.to_x === undefined || args.to_y === undefined)
        throw new Error('desktop drag needs from_x, from_y, to_x, to_y')
      Object.assign(params, { from_x: Number(args.from_x), from_y: Number(args.from_y), to_x: Number(args.to_x), to_y: Number(args.to_y) })
    } else if (action === 'scroll') {
      Object.assign(params, { x: Number(args.x) || 0, y: Number(args.y) || 0, direction: args.direction || 'down', pages: Number(args.pages) || 1 })
    } else if (action === 'type') {
      if (!args.text) throw new Error('desktop type needs text')
      Object.assign(params, { text: String(args.text) })
      if (args.window) Object.assign(params, { window_id: String(args.window) })
    } else if (action === 'press_key') {
      if (!args.key) throw new Error('desktop press_key needs key')
      Object.assign(params, { key: String(args.key) })
      if (args.window) Object.assign(params, { window_id: String(args.window) })
    } else if (action === 'state') {
      if (!args.window && !args.selector) throw new Error('desktop state needs window (id) or selector')
      Object.assign(params, args.window ? { window_id: String(args.window) } : { name: String(args.selector) })
    } else if (action === 'set_value') {
      if (args.selector === undefined || args.value === undefined) throw new Error('desktop set_value needs selector + value')
      Object.assign(params, { name: String(args.selector), value: String(args.value) })
    } else if (action === 'perform_action') {
      if (!args.selector) throw new Error('desktop perform_action needs selector')
      Object.assign(params, { name: String(args.selector) })
      if (args.actionName) Object.assign(params, { action: String(args.actionName) })
    } else if (action === 'focus') {
      if (!args.address && !args.selector) throw new Error('desktop focus needs address or selector')
      Object.assign(params, args.address ? { window_id: String(args.address) } : { name: String(args.selector) })
    } else if (action === 'windows' || action === 'focused' || action === 'move_window' || action === 'resize_window') {
      if (action === 'move_window' || action === 'resize_window') {
        if (args.address === undefined || args.x === undefined || args.y === undefined || (action === 'resize_window' && (args.w === undefined || args.h === undefined)))
          throw new Error('desktop ' + action + ' needs address + x/y' + (action === 'resize_window' ? ' + w/h' : ''))
        Object.assign(params, { window_id: String(args.address) })
        if (action === 'move_window') Object.assign(params, { x: Number(args.x), y: Number(args.y) })
        else Object.assign(params, { width: Number(args.w), height: Number(args.h) })
      }
    }
    const toolName = {
      type: 'type_text',
      press_key: 'press_key',
      windows: 'list_windows',
      focused: 'focused_window',
      focus: 'activate_window',
    }[action] ?? action
    const res = await mcp.callTool(toolName, params)
    return { backend: 'cul', result: typeof res === 'string' ? res.slice(0, 4000) : res }
  } finally { mcp.stop() }
}

const desktopTool = defineTool({
  name: 'desktop',
  description:
    'Linux desktop control (Hyprland), layered: native zero-daemon (hyprctl windows/focus/move/resize, '
    + 'grim screenshot, wtype type/press_key) plus computer-use-linux MCP for click/drag/scroll/state '
    + 'by pixel or semantic selector. CUL spawns per call and exits; no daemons are started. '
    + 'Action selects the operation; backend auto/native/cul picks the layer. '
    + 'Preferred for human-like GUI interaction (real windows, AT-SPI semantics, local vision); use browser (CDP) only for programmatic page access.',
  parameters: {
    action: {
      type: 'string',
      required: true,
      description: 'doctor | windows | focused | screenshot | focus | move_window | resize_window | type | press_key | click | drag | scroll | apps | state | set_value | perform_action',
    },
    backend: {
      type: 'string',
      description: 'auto (default) | native | cul — layer selection.',
    },
    address: { type: 'string', description: 'Window address (hyprctl 0x…) for focus/move/resize.' },
    window: { type: 'string', description: 'Window id/title for CUL type/press_key/state targeting.' },
    x: { type: 'integer' }, y: { type: 'integer' },
    w: { type: 'integer', description: 'Width for resize_window.' },
    h: { type: 'integer', description: 'Height for resize_window.' },
    from_x: { type: 'integer' }, from_y: { type: 'integer' },
    to_x: { type: 'integer' }, to_y: { type: 'integer' },
    direction: { type: 'string', description: 'scroll direction: up | down (default down).' },
    pages: { type: 'integer', description: 'scroll pages (default 1).' },
    text: { type: 'string', description: 'Literal text for type.' },
    key: { type: 'string', description: 'Key/combo for press_key, e.g. ctrl+shift+t, super+Return.' },
    selector: { type: 'string', description: 'Semantic selector (AT-SPI name/label) for click/state/set_value/perform_action.' },
    index: { type: 'integer', description: 'Element index for click (CUL accessibility tree order).' },
    value: { type: 'string', description: 'Value for set_value.' },
    actionName: { type: 'string', description: 'Accessibility action name for perform_action.' },
    path: { type: 'string', description: 'Screenshot output path (default /tmp/dsh-shot-<ts>.png).' },
  },
  output: {
    schema: { type: 'object', additionalProperties: true },
    render: (_args, value) => [{ type: 'text', text: JSON.stringify(value, null, 2) }],
  },
  isConcurrencySafe: () => false,
  timeoutMs: 25_000,
  async execute(args, exec) {
    const action = args.action
    const backend = args.backend ?? 'auto'
    const culBin = resolveCul(exec?.config)
    const useNative = backend === 'native' || (backend === 'auto' && !culOnly.has(action))
    const useCul = backend === 'cul' || (backend === 'auto' && culOnly.has(action)) || !useNative

    if (action === 'doctor') {
      const [native, cul, atspi] = await Promise.all([
        nativeDoctor(),
        culDoctor(culBin),
        atspiApps(culBin).then((r) => ({ ok: !r.error, error: r.error ?? null })),
      ])
      return { native, cul, atspi, note: 'auto uses native for windows/focused/screenshot/focus/move/resize/type/press_key; CUL spawns per call for click/drag/scroll/state/set_value/perform_action' }
    }
    if (action === 'apps') return atspiApps(culBin)
    if (useNative) {
      if (action === 'windows') return { backend: 'native', windows: await nativeWindows() }
      if (action === 'focused') return { backend: 'native', window: await nativeFocused() }
      if (action === 'screenshot') return { backend: 'native', ...(await nativeScreenshot(args, exec?.cwd ?? '/tmp')) }
      if (action === 'focus') return { backend: 'native', ...(await nativeFocus(args.address)) }
      if (action === 'move_window') return { backend: 'native', ...(await nativeMoveWindow(args.address, args.x, args.y)) }
      if (action === 'resize_window') return { backend: 'native', ...(await nativeResizeWindow(args.address, args.w, args.h)) }
      if (action === 'type') return { backend: 'native', ...(await nativeType(args.text)) }
      if (action === 'press_key') return { backend: 'native', ...(await nativePressKey(args.key)) }
    }
    if (useCul) return runCul(culBin, action, args)
    throw new Error('desktop: no backend for ' + action)
  },
})

export function apply(ctx) {
  ctx.tools.register(desktopTool)
}
