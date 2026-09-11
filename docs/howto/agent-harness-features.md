# Harness features: backlog (from omp / oh-my-opencode)

These are not prompts, but harness features — candidates for implementation in DSH/wrappers.
Recorded as a backlog with sources.

## 1. Hashline: edits anchored to line hashes (oh-my-opencode)

Problem: the "harness problem" — most agent errors are not in the model, but in the edit tool.
Solution: every read line gets a tag `{line}#{hash}` (CID alphabet `ZPMQVRWSNKTXJBYH`, 2
characters); edits reference the tags, and on a hash mismatch the edit is rejected before
corruption.

- Operations: replace / append / prepend; autocorrect on line shifts.
- Errors: hash mismatch, invalid reference, overlapping ranges.
- Claimed effect (README): Grok Code Fast edit success 6.7% → 68.3%.
- In omp the analogue is `[FILENAME#TAG]` snapshots in read.

Status: harness feature, separate research/task.

## 2. Candidate hooks (oh-my-opencode, 46 items in 3 tiers)

### Small, immediately useful

- **category-skill-reminder**: reminds to load the skills matching the selected delegation category.
- **agent-usage-reminder**: reminds to use specialized agents/tools.
- **compaction-todo-preserver**: preserves the todo list across session compaction.
- **rules-injector**: injects rules (`rules/*.md` with glob conditions and alwaysApply) on read.

### Feasibility assessment (2026-08-20, facts from the repo/store)

| Hook                                    | Seam in DSH                                                                   | Complexity | Recommendation                                                   |
| --------------------------------------- | ----------------------------------------------------------------------------- | ---------- | ---------------------------------------------------------------- |
| notepad-write-guard                     | `tools/pre-execute` deny on write/edit for .agent/notepads/\*\*               | low        | ✅ **implemented** (dsh-notepad-write-guard, 6/6 tests)          |
| plan-format-validator                   | `tools/pre-execute` deny on exit_plan_mode (heading + sections + body)        | medium     | ✅ **implemented** (dsh-plan-format-validator, 8/8 tests)        |
| task-resume-info                        | `session/event` session/end-seed + agent/pre-step inject                      | medium     | ✅ **implemented** (dsh-task-resume-info, 10/10 tests)           |
| delegate-task-retry                     | agent/pre-step + last tool error from subagent → retry inject                 | medium     | ✅ **implemented** (dsh-delegate-task-retry, 7/7 tests)          |
| edit/json-error-recovery                | agent/pre-step + last tool error → steer with a hint                          | low        | ✅ **implemented** (dsh-json-error-recovery, 7/7 tests)          |
| preemptive-compaction                   | `compaction/start` / context-meter (JObwrW_trigger data-pct) + ctx.compaction | high       | 🟡 defer (built-in limit already exists; double-compaction risk) |
| anthropic-context-window-limit-recovery | agent/request-error (overflow code) → steer                                   | medium     | 🟡 defer (rare on local models)                                  |
| atlas (master of background sessions)   | notepads.md + plan-before-code.md workflows already cover it                  | —          | ✅ covered by workflow (not a plugin)                            |
| unstable-agent-babysitter               | agent/status (idle cycles) + boulder mechanics                                | medium     | 🟡 defer (overlaps with boulder)                                 |
| keyword-detector                        | agent/pre-step + last user text regex → hint                                  | low        | ✅ **implemented** (dsh-keyword-detector, 7/7 tests)             |

Summary: **implemented** — notepad-write-guard, edit/json-error-recovery, keyword-detector (all
small, one recipe: pre-step + inject). **Covered by workflow** — atlas. **Defer** — the rest (no
seam / overlap / double-compaction risk).

### Large (already partially ported as prompts)

- **todo-continuation-enforcer** (boulder): exact text in `agent-guards.md` §6; mechanics (countdown
  2s, backoff 30s×2, max 5, 5-minute pause) — ✅ implemented by the dsh-boulder plugin.
- **preemptive-compaction**: preemptive compaction before the token limit — 📐 design ready:
  micro-compaction (continuous amortized compaction after every turn, port from hermes-agent) —
  `agent-micro-compaction.md`; implementation by the dsh-micro-compaction plugin is a separate task
  (medium priority).
- **anthropic-context-window-limit-recovery**: recovery after exceeding the context window — 🟡
  deferred.
- **atlas**: master of boulder/background sessions (orchestrating continuations) — ✅ covered by the
  notepads.md workflow.
- **unstable-agent-babysitter**: monitoring unstable agent behavior between sessions — 🟡 deferred.
- **keyword-detector**: triggers on message keywords (mode switching, etc.) — ✅ queued for
  implementation.

## 3. Misc

- Skill-embedded MCP: MCP server inside a skill, isolated by the `sessionID:skill:server` key (no
  state leaks between sessions).
- Scoped permissions for skills (a skill brings its own access boundaries).
- Wisdom notepads: `.omo/notepads/{plan}/learnings|decisions|issues|verification|problems.md`,
  passed to all subsequent subagents (already reflected in plan-before-code/delegate-task).
