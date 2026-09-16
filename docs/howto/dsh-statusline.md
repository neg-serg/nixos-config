# dsh status line

> Tianshu generation: the `tui` profile now runs dsh-TUI — see
> [dsh-tui-profile.md](./dsh-tui-profile.md). dsh-TUI does not read `DSH_TUI_STATUSLINE`, so the
> frame patch below is dormant while it is installed; the `dsh-statusline` helper itself is
> unchanged.

A session status line for dsh: branch (or worktree), how dirty the tree is, context usage, the turn
number, cost. The content lives in `packages/local-bin/bin/dsh-statusline` — session state arrives
as JSON on stdin, the first line of stdout is the status line — and two surfaces can render it.

## The frame surface (primary)

Upstream Tianshu **ships** a scriptable status line: `StatusLineRunner`, documented as "aligned with
the Claude Code `statusLine` protocol", configured through `ui.statusLine.command`, with a 3 s
throttle, single flight and a 2 s timeout kill. In the pinned `0.1.2-rc.29` that class is **exported
but never instantiated** — the bundle contains exactly one `shell: true` spawn (inside the runner
itself) and no `new StatusLineRunner(...)`, because the app renders its own `WorkflowStatusLine`
(phase · tool · badges) through `MetricsGlanceController` instead. So the feature cannot be switched
on from configuration: the slot above the input belongs to the TUI.

`dsh-tui-ru.nix` therefore patches it in, with four `FIXES` entries in `dsh-tui-ru-assets/patch.mjs`
(`tui-statusline-helper`, `-fields`, `-mount`, `-glance`):

1. insert `resolveStatusLineCommand(ctx)` (env `DSH_TUI_STATUSLINE`, else the documented
   `ui.statusLine.command`, else nothing) plus the `globalThis.__dshTuiStatusLineFrame` marker;
1. declare the `userStatusLine` / `userStatusLinePayload` fields;
1. construct the runner in `mountSession` when a command is configured;
1. drive it from the existing render loop — `MetricsGlanceController.getStatusText` refreshes the
   runner and returns `"<script output> · <workflow phase>"`.

The slot holds **one** line, so the script output is combined with the built-in phase/tool text
rather than replacing it: the workflow status is the reason that line exists. Every insertion is
defensive (try/catch, no runner when no command is configured), so a drifted bundle degrades to the
previous behaviour.

`dsh.nix` points `DSH_TUI_STATUSLINE` at the helper from the `dsh` wrapper, so plain
`dsh --profile tui` gets it; the variable is overridable and the wrapper skips it when the helper is
not installed.

## The title surface (fallback)

The TUI never writes OSC 0/1/2, so a plugin can own the terminal title without fighting it. The
`dsh-statusline` plugin does exactly that — same script, same protocol — and it is the fallback for
when the frame patch does not apply (a drifted or newer bundle). To keep the two from rendering at
once, the patched frame publishes `globalThis.__dshTuiStatusLineFrame` and the plugin stands down
while that marker is present:

| `DSH_STATUSLINE_TARGET` | Behaviour                                        |
| ----------------------- | ------------------------------------------------ |
| unset                   | frame when the patch is present, title otherwise |
| `title`                 | title only                                       |
| `both`                  | both surfaces                                    |

```text
frame:  ◆ ⎇ main · ✚1 · turn 7      (the ◆ status marker, above the input box)
title:  ⎇ main · ◆2 ✚5 ?2 · ctx 42% · turn 7 · ¥0.123
```

## Protocol

The script speaks the documented Tianshu payload (a Claude-Code subset), so it also plugs into the
upstream runner unchanged:

```json
{
  "session_id": "…",
  "turn": 7,
  "model": { "display_name": "deepseek-v4" },
  "workspace": { "current_dir": "/path/to/repo" },
  "git": { "branch": "main" },
  "context": { "ratio": 0.42, "estimated_tokens": 54000, "max_tokens": 128000 },
  "cost": { "total_yuan": 0.1234 }
}
```

Every field is optional. The frame passes `session_id`, `workspace.current_dir` and
`model.display_name`; the title path additionally derives `context.estimated_tokens` (input +
cache-read tokens from the last `assistant/message`, the input-side definition) and `turn`. The
script runs `git status` itself for the dirty counts.

### Script modes

```sh
dsh-statusline                 # protocol mode: JSON on stdin → one line on stdout
dsh-statusline --git [DIR]     # only the git/worktree segment
dsh-statusline --demo          # protocol mode against a canned payload
dsh-statusline --help
```

| Env                     | Effect                                                                                                                      |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `DSH_STATUSLINE_PARTS`  | comma list of segments to keep: `place,state,context,turn,cost` (default all)                                               |
| `DSH_WORKTREE_ROOT`     | trees under this root are labelled `wt:<name>` instead of by branch (default `~/.dsh/worktrees`, the `dsh-worktree` layout) |
| `DSH_TUI_STATUSLINE`    | the command the frame and the plugin run                                                                                    |
| `DSH_STATUSLINE`        | `0`/`false` disables the title plugin                                                                                       |
| `DSH_STATUSLINE_CMD`    | replace the script for the title plugin                                                                                     |
| `DSH_STATUSLINE_TARGET` | `title` / `both` to override the frame-first handshake                                                                      |

## Steady-state behaviour

Copied from the upstream runner, because the reasons are identical: refresh is **throttled**
(default 3 s), **single-flight** (a request while the previous run is outstanding is skipped), the
previous text is kept when the script fails, times out or prints nothing, and an unchanged title is
not written twice. The title path strips control characters and caps the line at 300 characters, so
a buggy user script cannot inject an escape sequence.

## Verification

Unit level:

- `modules/user/nix-maid/apps/dsh-tui-ru-assets/statusline-frame.test.mjs` (41 assertions) — the
  four anchors exist and are extracted from the real patcher source, each fix declares a `probe` so
  a re-run cannot duplicate it, the patched bundle parses, a re-run is byte-identical and leaves
  exactly one runner construction, `resolveStatusLineCommand` resolves env → `ui.statusLine.command`
  → dashed key → null and never throws, and the combined status text keeps the workflow line;
- `modules/user/nix-maid/apps/dsh-statusline/test.mjs` (34 assertions) — payload, OSC 1/2 encoding,
  gates, throttle, failure modes, and the frame-first handshake;
- `scripts/dev/check-dsh-statusline.sh` (19 assertions) — branch and dirty counts, `wt:<name>`,
  context from ratio and from tokens/max, `DSH_STATUSLINE_PARTS`, graceful degradation, the
  `--git`/`--demo`/`--help` modes. Wired into `just check` as `dsh-statusline-guard`.

Runtime level (PTY, `script -qec 'stty rows 40 cols 120; dsh --profile tui'`):

- with `DSH_TUI_STATUSLINE` set to a tracing command, the runner invoked it (10 calls in one
  session) and its output reached the rendered frame;
- with the real script, the frame shows `◆ ⎇ smoke · ✚1`;
- with no command configured, the patched frame is **byte-identical** to the pre-patch run (only
  `script`'s own timestamps differ), i.e. zero behavioural change.

### Marker semantics

The patch marker records the hash of the bundle the run **produced**, not the one it read, so "up to
date" is true only while the file on disk is still the patcher's own output. It used to record the
pre-patch hash, which made a bundle restored to its pristine state (a backup, a reverted edit, a
pnpm re-install) look patched while the fixes were absent — the patcher then skipped them silently.
`notify-osc.test.mjs` pins the regression: restore the `.orig` fixture and the next run must
re-apply.
