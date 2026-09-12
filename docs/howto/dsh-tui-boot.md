# dsh TUI: what happens while it boots

Why `dsh --profile tui` shows nothing for a moment, what the boot progress line reports, and how to
turn it off.

## Where the time goes

The harness boots the terminal profile in stages before the TUI paints its first frame. The phases,
measured on odin with a warm page cache (a pty run from `--profile tui`):

| Phase                                                       | Cumulative |
| ----------------------------------------------------------- | ---------- |
| node start + `bin.js` + profile composition + first plugins | ~0.23 s    |
| the TUI plugin mounts (`apply()` runs)                      | ~0.30 s    |
| `sessions` / `agents` / `agentDefaultModel` services ready  | ~0.31 s    |
| `settings` / `credentials` ready, plugin tree settled       | ~0.39 s    |
| first painted frame                                         | ~0.6 s     |

So a warm start is under a second, and the silent part is the ~0.4 s between process start and the
first frame. The number can grow well beyond that in two cases:

- **Cold nix-store page cache** (first launch after boot): importing the ~50 plugins and the 1.1 MB
  TUI bundle reads from disk.
- **A large session resume**: `attach()` calls `ctx.sessions.list()[0]` and reopens the most recent
  session for the working directory. `~/.dsh/sessions/--etc-nixos--` is ~460 MB with sessions up to
  ~57 MB, and decoding one blocks the first frame.

Both are silent without the patch below: the terminal just sits there.

## What the patch adds

`modules/user/nix-maid/apps/dsh-tui-ru-assets/patch.mjs` carries the `boot-progress-*` fixes. They
render one self-clearing status line on stdout while `attach()` runs, shaped as
`<spinner> <phase> <elapsed>s`. The copy is Russian (the TUI is localized); the phases, in order,
are booting dsh, initializing the TUI, host services, settings and credentials, and session resume.
A warm boot shows the first two or three and is gone in well under a second; a cold or session-heavy
boot keeps the spinner and the elapsed counter moving.

- The helper (`createBootProgress`) is the only insertion; the phases are wired to unique anchors in
  `apply()` and `TuiApp.attach()`.
- The line is drawn as soon as the runner mounts, ticks every 120 ms, and is wiped at the top of
  `flushLiveRender()` — the first frame can come from a session switch or the welcome, so stopping
  only at the end of `attach()` would overwrite it. A `.finally()` on the attach promise clears the
  line on the failure path too.
- Off a TTY (piped output, `--help`/`--version` with a redirected stream, test harness) the helper
  is a complete no-op.

## Knobs

| Knob                   | Effect                                      |
| ---------------------- | ------------------------------------------- |
| `DSH_TUI_BOOT_QUIET=1` | Disable the boot line (`true` works too).   |
| `CI=1` / `VITEST=1`    | Disabled automatically (test environments). |

## Where it lives / how to verify

- Patch: `modules/user/nix-maid/apps/dsh-tui-ru-assets/patch.mjs` (`boot-progress-*` fix ids),
  applied by the activation script in `dsh-tui-ru.nix` to every installed `dsh-tianshu-tui` bundle.
- Test: `node modules/user/nix-maid/apps/dsh-tui-ru-assets/boot-progress.test.mjs` — covers the
  patcher mechanics (anchors applied, idempotent re-runs, the patched bundle parsing) and the helper
  contract (no-op off a TTY and under the kill switches, immediate phase draws, cleared exactly
  once).

## Related

- The TUI also runs a self-update check at startup (`registry.npmjs.org`, then
  `registry.npmmirror.com`, 3 s timeout each). It is a background task; when it decides to install,
  pnpm runs while the UI is already up and a blank session is restarted afterwards. Disable with
  `DSH_TUI_SKIP_UPDATE=1`.
- `docs/howto/dsh-tui-notifications.md` — the same patcher's completion-notification fixes.
