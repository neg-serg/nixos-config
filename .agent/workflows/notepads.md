______________________________________________________________________

## description: Cumulative notepad memory for multi-step plans (Atlas notepad system, ported from oh-my-opencode)

______________________________________________________________________

# Notepads

Subagents are stateless. A notepad is the plan's cumulative intelligence: it carries what each task
learned across every delegation, so no task re-derives conventions, re-makes decisions, or re-hits
known gotchas. Keep one notepad per plan under `.agent/notepads/{plan-name}/`.

## When to create

1. **Create a notepad for any plan with 3+ distinct steps** — the same trigger as plan-before-code.
   Shorter single-step work does not need one.

1. **Use the plan name as the directory name** (kebab-case, no spaces):
   `.agent/notepads/{plan-name}/`.

1. **Scaffold all five files before the first delegation**, so every subagent has a stable place to
   read from and append to. If the directory is missing later, recreate it with the same files.

## The five files

1. **`learnings.md`** — patterns, conventions, and successes: how this repo is actually laid out,
   which idioms already work, and what a successful task did right.

   ```markdown
   ## [TIMESTAMP] Task: {task-id}
   - Pattern: ...
   - Convention: ...
   - Success: ...
   ```

1. **`decisions.md`** — choices made and why, so later tasks do not silently reverse them.

   ```markdown
   ## [TIMESTAMP] Task: {task-id}
   - Decision: ...
   - Rationale: ...
   - Alternatives rejected: ...
   ```

1. **`issues.md`** — problems and gotchas that cost time or broke a task, with the workaround.

   ```markdown
   ## [TIMESTAMP] Task: {task-id}
   - Problem: ...
   - Cause: ...
   - Workaround / fix: ...
   ```

1. **`verification.md`** — test and verification results: command, expected output, actual output,
   and pass/fail.

   ```markdown
   ## [TIMESTAMP] Task: {task-id}
   - Command: ...
   - Expected: ...
   - Actual: ...
   - Result: PASS / FAIL
   ```

1. **`problems.md`** — unresolved blockers and tech debt left open on purpose; read before declaring
   completion.

   ```markdown
   ## [TIMESTAMP] Task: {task-id}
   - Open problem: ...
   - Impact: ...
   - Owner / next step: ...
   ```

## Rules

1. **Read before delegating.** Before every delegation, read the notepad files and include the
   relevant excerpts in the subagent prompt under "Inherited Wisdom". Never delegate blind.

1. **Update after each task.** After a task finishes and is verified, append its findings to the
   matching file. Append only; never overwrite or erase previous entries.

1. **Pass learnings to ALL subsequent subagents.** Not just the next one — every subagent in the
   plan gets the accumulated learnings, decisions, issues, and known problems that apply to it.

1. **Current repo state beats stale notepad.** A notepad is a hint, not a license to skip
   inspection. When a notepad entry disagrees with the repo as it is now, trust the repo and correct
   the notepad.

1. **Keep files small.** One entry per task, a few tight bullets per entry. If a file grows past a
   screenful, summarize the oldest entries and keep only what still applies. Drop trivia and
   re-derivable facts.

## Notes

- Format each entry with `## [TIMESTAMP] Task: {task-id}` so entries stay greppable and ordered.
- Use the plan name consistently: `.agent/notepads/{plan-name}/` mirrors the plan that started the
  work, so the notepad travels with its plan across sessions.
- Append-only keeps history intact; correct a wrong entry by adding a newer entry that supersedes it
  rather than editing the old one away.
