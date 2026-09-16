# dsh TUI: completion notifications through the terminal (OSC)

> Tianshu generation: the `tui` profile now runs dsh-TUI — see
> [dsh-tui-profile.md](./dsh-tui-profile.md). The OSC patch below applies to Tianshu bundles only
> and is dormant while dsh-TUI is installed.

How the Tianshu TUI (`@huiliyi37/dsh-tianshu-tui`, profile `~/.dsh/profiles/tui`) tells you a turn
finished, and why the shipped path had to be replaced.

## The problem with the shipped path

Upstream implements `notifyOs()` as a subprocess: `notify-send` on Linux, `osascript` on macOS,
PowerShell on Windows. Two consequences:

- `notify-send` talks to the **session D-Bus**, so it is useless over SSH. Upstream works around
  that by refusing to notify at all when `SSH_CONNECTION` / `SSH_CLIENT` / `SSH_TTY` is set
  (`shouldNotify()`), which also disables the notification for a perfectly capable remote terminal.
- Terminals that implement the **OSC notification protocols** (kitty, iTerm2, WezTerm, Ghostty) are
  never used even locally, so the notification looks like a generic "notify-send" bubble instead of
  one attributed to the terminal/tab.

The TUI's separate terminal-bell channel (`term-bell`, a raw `\x07` on the pty) is correct and is
deliberately left alone: it already survives SSH, and it shares the same `/config notify` switch.

## What the patch does

`dsh-tui-ru-assets/patch.mjs` carries a `FIXES` entry with id **`notify-osc`**. It rewrites
`notifyOs()` to try a terminal-native notification first and fall back to the old subprocess path:

| Situation                                                               | Protocol                           | Emitted                        |
| ----------------------------------------------------------------------- | ---------------------------------- | ------------------------------ |
| `KITTY_WINDOW_ID` set, or `TERM` has kitty                              | OSC 99                             | `\e]99;;<title — body>\e\\`    |
| `TERM_PROGRAM` = `iTerm.app`/`WezTerm`/`ghostty`, or `TERM` has ghostty | OSC 9                              | `\e]9;<title — body>\a`        |
| any other terminal                                                      | none — falls back to `notify-send` | (unchanged upstream behaviour) |

Because the sequence is written to the TUI's own stdout, it is **just bytes on the pty**: no session
bus, no subprocess, and it works over SSH. This is the regression the test guards.

Both sequences are control-only: they never touch the visible text grid, so interleaving them with
the TUI renderer is safe, and the payload is passed through the same `sanitizeNotifyText()` (control
characters clamped to spaces, title ≤ 80, body ≤ 200) so a message can never inject its own escape
sequence.

The OSC path is only taken when `process.stdout.isTTY` is true, so a redirected/piped stdout keeps
the old behaviour rather than silently swallowing the notification.

## Switches

| Knob                    | Effect                                                                                                      |
| ----------------------- | ----------------------------------------------------------------------------------------------------------- |
| `/config notify off`    | `prefs.notifyOs = false` in `~/.dsh-tui/prefs.json` — disables OSC **and** the bell (same gate as upstream) |
| `DSH_TUI_SKIP_NOTIFY=1` | environment kill-switch (locks the `/config` toggle, as upstream does)                                      |
| `DSH_NOTIFY_OSC=0`      | force the legacy `notify-send` path even in a capable terminal                                              |
| `DSH_NOTIFY_OSC=1`      | force OSC 9 even in a terminal the detection does not recognise                                             |

## Multiplexers

- **kitty** is the terminal here and needs no configuration for OSC 99 / OSC 9.
- **tmux** swallows escape sequences unless `allow-passthrough on` is set; that is not in the repo
  because tmux is not installed on odin (zellij is).
- **zellij** is installed but its OSC pass-through is **not verified**. If notifications stop
  appearing inside zellij, set `DSH_NOTIFY_OSC=0` — the local `notify-send` fallback still fires,
  and the bell is unaffected either way.

## Where it lives / how to verify

- Patch: `modules/user/nix-maid/apps/dsh-tui-ru-assets/patch.mjs` (fix id `notify-osc`), applied by
  the activation script in `dsh-tui-ru.nix` to every installed `dsh-tianshu-tui` bundle.
- Test: `node modules/user/nix-maid/apps/dsh-tui-ru-assets/notify-osc.test.mjs` — 38 assertions
  covering patcher mechanics (insert, rewire, idempotency, `.orig` backup, marker) and the protocol
  decision table, including the SSH case and the non-TTY guard.

### Marker semantics

The marker records the hash of the bundle the run **produced**, not the one it read, so `up to date`
is true only while the file on disk is still the patcher's own output — the fast path engages on the
first run after patching. It used to record the pre-patch hash, which made a bundle restored to its
pristine state (a backup, a reverted edit, a pnpm re-install) look patched while the fixes were
absent; the patcher then skipped them silently. `notify-osc.test.mjs` pins the regression, and
[dsh-statusline.md](dsh-statusline.md) documents the same semantics.

## Input-needed notifications

This patch covers work that **finished**. The two requests that block a turn — the approval card and
the structured question — are covered by the `dsh-notify-input` plugin instead, which registers
ahead of the TUI's waterfall handlers and reuses the protocol table above: see
[dsh-notify-input.md](dsh-notify-input.md).
