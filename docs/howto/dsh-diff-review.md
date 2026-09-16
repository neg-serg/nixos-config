# dsh diff review: the `show_diff` tool and `/diff`

Claude Code opens a persistent `/diff` pane beside the conversation; Codex has `/diff`; Aider has
`/diff` plus git-backed `/undo`. dsh had no review surface at all — only the inline diff inside a
single edit's approval card.

## Why this is a tool first and a command second

Two harness facts decide the design:

- A slash command can only return `{ kind, text }` (`CommandResult` in `@deepseek-ai/dsh-commands`)
  — it cannot carry a presentation.
- A **tool** declares `output.presentationMeta(args, value)` and `presentResult(args, result)`, and
  a UI maps the returned `ToolCallView` union. `card: "diff"` with `diffs: FileDiff[]` is the same
  presenter the edit-approval preview uses, so a capable TUI (dsh-TUI) renders structured red/green
  file diffs.

So the review surface is the `show_diff` tool, and `/diff` is the textual entry point for the human.

```text
/diff                     # uncommitted changes (git diff HEAD): files, totals, untracked list
/diff src/app.js          # narrow to a path
/diff --staged            # the index (git diff --cached)
/diff --ref origin/main   # compare against a ref
/diff --patch             # include the unified diff in the reply
```

Asking the agent to review the changes makes it call `show_diff`, which produces the card.

## The diff is rebuilt from the patch, not from the files

`FileDiff` wants `{ path, oldText, newText }`, and the obvious implementation is one `git show` per
changed file plus a file read for the working copy. That is rejected deliberately:

- it costs one subprocess **per file** (plus the `fs` service and its sandbox policy), for what is
  one `git diff`;
- the changed hunks are already in the patch.

Instead `presentationMeta` (pure and synchronous) parses the patch: for each file, `oldText` is its
context + removed lines and `newText` its context + added lines, so the card re-diffs those two and
reproduces the same change. Consequences, all intended:

- the card shows the **changed regions**, not the whole file — which is what a review is for;
- a `new file mode` block becomes `oldText: null`, the presenter's contract for a create;
- a deleted file becomes `newText: ""`;
- `Binary files … differ` blocks are flagged and carry no line counts;
- mode-only and rename-without-content blocks legitimately render `+0 −0`.

## Limits (by design)

| Limit                                       | Why                                                                               |
| ------------------------------------------- | --------------------------------------------------------------------------------- |
| Untracked files are **listed**, not diffed  | `git diff` never shows them; diffing them would need a file read per path         |
| Card capped at 40 files, 512 KiB per stream | a tool result must stay readable, and `readFrom` is the only collected-output API |
| A persistent side pane is not provided      | the TUI owns its layout; a plugin can render a card, not reserve screen space     |
| `/diff` shows the patch only with `--patch` | the default reply stays a summary; the card is the readable form                  |

## Verification

`modules/user/nix-maid/apps/dsh-diff/test.mjs` — 56 assertions: the patch parser (modify/create/
delete/binary/quoted paths with spaces/`\ No newline at end of file`/empty input), the full tool
contract (`execute` → `presentationMeta` → `presentResult`, plus the `undefined` card for an empty
diff), the git argv for every target, and the `/diff` argument handling.

The parser was additionally run against **real** `git diff HEAD` output from a repository holding a
modification, a deletion, a file with spaces in its name, a file without a trailing newline, a
binary, and a rename with a mode change: 6 files parsed, 0 `FileDiff` violations.
