# dsh status line

A session status line for dsh: branch (or worktree), how dirty the tree is, context usage, the turn
number, cost. The content lives in `packages/local-bin/bin/dsh-statusline` — session state arrives
as JSON on stdin, the first line of stdout is the status line — and the `dsh-statusline` plugin
(`modules/user/nix-maid/apps/dsh-statusline`) renders it in the terminal title.

## Why the title and not the frame

The `tui` profile used to run the Tianshu TUI, whose bundle **ships but never instantiates** a
scriptable status line (`StatusLineRunner`, "aligned with the Claude Code `statusLine` protocol").
That gap was closed by a patch in the (now removed) Tianshu localization layer, which mounted the
runner into the render slot above the input.

dsh-TUI is a different codebase: it renders its own status line and does not read
`DSH_TUI_STATUSLINE`, so that patch is gone. What a plugin can still own is the **terminal title** —
the TUI never writes OSC 0/1/2, so the title is free:

```text
title:  ⎇ main · ◆2 ✚5 ?2 · ctx 42% · turn 7 · ¥0.123
```

## Protocol

The script speaks the documented Claude-Code-compatible payload:

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

Every field is optional. The plugin passes `session_id`, `workspace.current_dir` and
`model.display_name`, and additionally derives `context.estimated_tokens` (input + cache-read tokens
from the last `assistant/message`, the input-side definition) and `turn`. The script runs
`git status` itself for the dirty counts.

### Script modes

```sh
dsh-statusline                 # protocol mode: JSON on stdin → one line on stdout
dsh-statusline --git [DIR]     # only the git/worktree segment
dsh-statusline --demo          # protocol mode against a canned payload
dsh-statusline --help
```

| Env | Effect | | ----------------------- |
------***----------***----------------------------------------- | | `DSH_STATUSLINE_PARTS` | comma
list of segments to keep: `place,state,context,turn,cost` (default all) | | `DSH_WORKTREE_ROOT` |
trees under this root are labelled `wt:<name>` instead of by branch (default `~/.dsh/worktrees`, the
`dsh-worktree` layout) | | `DSH_STATUSLINE` | `0`/`false` disables the title plugin | |
`DSH_STATUSLINE_CMD` | replace the script the plugin runs | | `DSH_STATUSLINE_TARGET` | `title` (the
only surface left) / `both` — kept for the plugin's own gate logic |

## Steady-state behaviour

Refresh is **throttled** (default 3 s), **single-flight** (a request while the previous run is
outstanding is skipped), the previous text is kept when the script fails, times out or prints
nothing, and an unchanged title is not written twice. The title path strips control characters and
caps the line at 300 characters, so a buggy user script cannot inject an escape sequence.

## Verification

Unit level:

- `modules/user/nix-maid/apps/dsh-statusline/test.mjs` (34 assertions) — payload, OSC 1/2 encoding,
  gates, throttle and failure modes;
- `scripts/dev/check-dsh-statusline.sh` (19 assertions) — branch and dirty counts, `wt:<name>`,
  context from ratio and from tokens/max, `DSH_STATUSLINE_PARTS`, graceful degradation, the
  `--git`/`--demo`/`--help` modes. Wired into `just check` as `dsh-statusline-guard`.

Runtime level (PTY, `script -qec 'stty rows 40 cols 120; dsh --profile tui'`):

- with the real script, the terminal title carries the status line (check the tab bar, or
  `kitty @ ls` / the terminal's own title query) while the TUI keeps its own in-frame status line.
