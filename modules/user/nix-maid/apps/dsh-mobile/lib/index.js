import { execFile, spawn } from 'node:child_process'
import { promisify } from 'node:util'

/**
 * dsh-mobile: slash command `/mobile` — connect the Android phone (adb over
 * USB or WiFi) and start scrcpy mirroring on the desktop.
 *
 * Connection logic lives in the `phone` helper (~/.local/bin/phone, see
 * packages/local-bin/bin/phone): `/mobile [ip]` connects and launches scrcpy
 * detached (so the command returns immediately), `/mobile status` just shows
 * `adb devices`.
 */

/** Cordis plugin name — must match the patch row / package name. */
export const name = 'dsh-mobile'

/** Required service: slash-command registry. */
export const inject = ['commands']

const HOME = process.env.HOME ?? '/home/neg'
const PHONE = `${HOME}/.local/bin/phone`

/**
 * dsh.service runs without DISPLAY/WAYLAND_DISPLAY; the user manager has them
 * (Hyprland session). Pass fallbacks so scrcpy can open a window on the
 * desktop even when launched from the host plugin.
 */
const DISPLAY_ENV = {
  DISPLAY: process.env.DISPLAY ?? ':0',
  WAYLAND_DISPLAY: process.env.WAYLAND_DISPLAY ?? 'wayland-1',
  XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR ?? `/run/user/${process.getuid ? process.getuid() : 1000}`,
}

const execFileP = promisify(execFile)

function runPhone(args, timeoutMs = 30000) {
  return execFileP(PHONE, args, { timeout: timeoutMs })
}

/** Launch scrcpy detached so the slash command returns immediately. */
function launchScrcpy(serial) {
  const child = spawn('scrcpy', ['-s', serial], {
    env: { ...process.env, ...DISPLAY_ENV },
    detached: true,
    stdio: 'ignore',
  })
  child.unref()
}

export function apply(ctx) {
  ctx.commands.register({
    name: 'mobile',
    description: 'подключить телефон: /mobile [ip|usb] — adb USB/WiFi + scrcpy, /mobile status',
    input: { hint: '[ip|usb|status]' },
    handler: async ({ rawInput }) => {
      const arg = rawInput.trim()
      try {
        if (arg === 'status') {
          const { stdout, stderr } = await runPhone(['status'])
          return { kind: 'success', text: (stdout + stderr).trim() }
        }
        const args = arg === '' ? ['connect'] : ['connect', arg]
        const { stdout, stderr } = await runPhone(args)
        const serial = stdout.trim()
        const warnings = stderr.trim()
        if (serial === '') {
          return { kind: 'error', text: warnings || 'телефон не найден' }
        }
        launchScrcpy(serial)
        const lines = [`телефон подключён: ${serial}`, 'scrcpy запущен (зеркало на рабочем столе).']
        if (warnings !== '') {
          lines.push('', warnings)
        }
        return { kind: 'success', text: lines.join('\n') }
      } catch (e) {
        const msg = (e && (e.stderr || e.message)) || String(e)
        return { kind: 'error', text: String(msg).trim() }
      }
    },
  })
}
