# dsh status line

A session status line for dsh: branch (or worktree), how dirty the tree is, context usage, the turn
number, cost. Two pieces:

- `packages/local-bin/bin/dsh-statusline` — the **content**: session state arrives as JSON on stdin,
  the first line of stdout is the status line;
- the `dsh-statusline` plugin — the **plumbing**: gathers session state, runs the script, and puts
  its output in the terminal title as OSC 2 / OSC 1.

## Why the title and not a line above the input

The Tianshu TUI **already ships** a scriptable status line — `StatusLineRunner`, documented as
"aligned with the Claude Code `statusLine` protocol", configured through `ui.statusLine.command`,
with a 3 s throttle, single flight and a 2 s timeout kill. In the pinned `0.1.2-rc.29` that class is
**exported but never instantiated**: the bundle contains exactly one `shell: true` spawn (inside the
runner itself) and no `new StatusLineRunner(...)`, and the app renders its own `WorkflowStatusLine`
(phase · tool · badges) through `MetricsGlanceController` instead. So the feature cannot be enabled
from configuration — the slot above the input is the TUI's.

The TUI also never writes OSC 0/1/2 (verified: no `\x1b]0;` / `]1;` / `]2;` anywhere in the bundle),
so a plugin can own the terminal title without fighting it. That is what this does:

```text
⎇ main · ◆2 ✚5 ?2 · ctx 42% · turn 7 · ¥0.123
wt:auth-fix · ✚1 · ctx 12%
```

Consequences worth knowing: the line is visible in the tab bar / window list even when the TUI is
scrolled, it is *not* a line above the input prompt, and it needs a terminal that honours OSC 1/2
(kitty, Ghostty, WezTerm, iTerm2 — kitty is what this host runs).

## Protocol

The script speaks the documented Tianshu payload (a Claude-Code subset), so if the upstream runner
is ever wired, the same script plugs in with no changes:

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

Every field is optional. The plugin supplies `session_id`, `turn`, `workspace.current_dir` and
`context.estimated_tokens` (input + cache-read tokens from the last `assistant/message`, the
input-side definition); the script runs `git status` itself for the dirty counts and reads the
branch from the repository.

### Script modes

```sh
dsh-statusline                 # protocol mode: JSON on stdin → one line on stdout
dsh-statusline --git [DIR]     # only the git/worktree segment
dsh-statusline --demo          # protocol mode against a canned payload
dsh-statusline --help
```

| Env                    | Effect                                                                                                                      |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `DSH_STATUSLINE_PARTS` | comma list of segments to keep: `place,state,context,turn,cost` (default all)                                               |
| `DSH_WORKTREE_ROOT`    | trees under this root are labelled `wt:<name>` instead of by branch (default `~/.dsh/worktrees`, the `dsh-worktree` layout) |
| `DSH_STATUSLINE`       | `0`/`false` disables the plugin entirely                                                                                    |
| `DSH_STATUSLINE_CMD`   | replace the script (any command; the plugin resolves it through the subprocess provider)                                    |

## Steady-state behaviour

Copied from the upstream runner, because the reasons are identical: a refresh is **throttled**
(default 3 s), **single-flight** (a request while the previous run is outstanding is skipped), the
previous title is kept when the script fails, times out or prints nothing, and an unchanged line is
not written again. Output is stripped of control characters and capped at 300 characters, so a buggy
user script cannot inject an escape sequence through the title. Nothing is written when stdout is
not a TTY.

## Verification

`modules/user/nix-maid/apps/dsh-statusline/test.mjs` — 32 assertions: the payload the script
receives, the OSC 1/2 encoding, first-line-only, no rewrite when unchanged, control-character
stripping, every gate (`DSH_STATUSLINE`, non-TTY, empty output, non-zero exit, missing helper, spawn
failure), the throttle, and the `agent/status` idle refresh.

`scripts/dev/check-dsh-statusline.sh` — 19 assertions against a throwaway dirty repository: branch
and the three dirty counts, `wt:<name>` naming, `context` from ratio *and* from tokens/max,
`DSH_STATUSLINE_PARTS`, graceful degradation on an empty payload, and the `--git` / `--demo` /
`--help` modes. Wired into `just check` as `dsh-statusline-guard`.
