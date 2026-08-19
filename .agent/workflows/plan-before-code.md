______________________________________________________________________

## description: Plan before code with plan QA (Prometheus/Metis/Momus pattern, ported from oh-my-opencode + omp)

______________________________________________________________________

# Plan Before Code

For any task with 3+ distinct steps, non-trivial ambiguity, or risk: produce a verified plan BEFORE
editing code. Do not stop on the plan alone — execute it right after.

## Steps

1. **Interview if ambiguous** (Prometheus-style, keep it short):

   - Success criteria — deterministic, verifiable (tests pass, exit 0, score >= N); reject vague
     "works well".
   - Scope boundaries — allowed files/dirs; explicit list of untouched items.
   - One question per turn, max ~6; if answers stay vague, draft the objective and confirm.

1. **Research read-only** (scout/librarian-style):

   - Explore the codebase with grep/glob/read before planning; parallelize independent reads.
   - Empty search result → try at least one alternate strategy before concluding absence.

1. **Write the plan** (decision-complete, ulw-plan style):

   - Goal: ONE plan a worker executes with ZERO further interview — explore a lot, ask few sharp
     questions (or none), stop the moment the plan is done.
   - Remaining execution-order steps: exact files, symbols, commands, checks.
   - Risks and edge cases; for each, the verification command and expected output.
   - Already-done work in brief, to prevent repetition.
   - NEVER modify tests or verification assets to make checks pass.
   - Approval gate: for non-trivial plans, pause for explicit user OK before executing; plan mode is
     sticky — "do X"/"fix X" mean "plan X" until the user approves execution.

1. **Gap analysis** (Metis-style): catch what the plan author missed — hidden intentions in the
   request, ambiguities that could derail implementation, over-engineering / scope creep, missing
   acceptance criteria, unaddressed edge cases.

1. **Plan QA** (Momus-style, approval-biased — reject only verified blockers):

   - Referenced files exist and support the plan's claims.
   - Every task gives a usable starting point; tasks do not contradict each other.
   - QA scenarios name the tool, steps, and expected result.
   - A plan roughly 80% clear is executable; minor details resolvable during implementation do NOT
     block. On rejection: fix every cited issue and re-check, no retry limit.
   - Plan-gate: deep reviews (Metis gap analysis / Momus-style) apply only when a written plan
     exists; a bare run without a plan file gets lighter self-review.

1. **Convert to todos**: 5-9 items, one per meaningful step; each with a concrete target +
   verification (omp prewalk rule). Exclude reporting/bookkeeping/cleanup ceremony.

1. **Execute** — checkpoint, not a stop: after the todo list, continue the task.

   - Parallel delegation is the default when subtasks are independent (Atlas rule); do NOT serialize
     independent work.
   - Anti-duplication: never run two delegations that would edit the same file/area — coordinate
     ownership first.
   - Verify personally after every delegation: does it work, does it follow existing patterns, did
     it respect MUST DO / MUST NOT DO? Fix or re-delegate on failure.
   - After 3 consecutive failures on one piece: change strategy, document attempts, do not blindly
     retry.

## Notes

- Plan lives in the session/`AGENTS.md` context, not in source files, unless the user asks for a
  written plan file.
- On new instructions arriving mid-task: capture them in todos before proceeding (AGENTS.md todo
  contract).
- Escalation: push back on risk-hidden plans with evidence (AGENTS.md "Agent reasoning").
