______________________________________________________________________

## description: Debug by Iron Law — root cause first, tight feedback loop (ported from hermes-agent systematic-debugging, adapted from obra/superpowers)

______________________________________________________________________

# Debugging (Iron Law)

Random fixes waste time and create new bugs. Quick patches mask underlying issues.

**Core principle:** ALWAYS find root cause before attempting fixes. Symptom fixes are failure.

**Violating the letter of this process is violating the spirit of debugging.**

## The Iron Law

NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST

If you haven't completed Phase 1, you cannot propose fixes.

## The Feedback Loop Rule

The feedback loop is the debugging work. Before reading code to build a theory, create or identify a
**tight** command that can go red on the user's exact symptom and green when the bug is fixed. A
tight loop is fast, deterministic, agent-runnable, and specific enough to catch this bug — not
merely "doesn't crash".

When a clean repro is hard, spend disproportionate effort building the loop. Guessing without a
red-capable loop is the failure mode this process exists to prevent.

## When to Use

Any technical issue: test failures, production bugs, unexpected behavior, performance problems,
build failures, integration issues. Especially under time pressure — emergencies make guessing
tempting.

## Phase 1 — Understand the bug (root cause, no fixes)

1. **Reproduce first.** Run the failing command / test yourself. Copy the exact error, don't
   paraphrase.
1. **Build the tight loop.** A command that exits non-zero on the symptom, zero when fixed.
   - Fast: seconds, not minutes.
   - Deterministic: same result every run.
   - Specific: catches THIS bug, not "doesn't crash".
   - If no repro exists: write the failing test / minimal script FIRST (TDD).
1. **Read the relevant code** only after the loop exists. Trace the actual data flow; don't theorize
   from memory.
1. **Form the root-cause theory** with evidence: exact file:line, call chain, state at failure.
   State the claim and what would prove it wrong.
1. **Confirm the theory** by making the loop go red for the claimed reason (e.g. instrument or
   bisect with git) — not by eye-balling.

## Phase 2 — Fix (only after Phase 1)

1. One fix targeting the confirmed root cause. No drive-by changes.
1. Make the loop go green. Run the FULL suite too — the fix must not break anything else.
1. Fix the whole bug class: sibling call paths, related call sites (hermes: "fixes the whole bug
   class — sibling call paths included — not just the one site the reporter hit").
1. If the fix needs a regression test that doesn't exist — add it (the loop becomes the test).

## Anti-patterns (blocking)

- Proposing a fix before Phase 1 complete → stop, go back.
- "It probably is X" without evidence → not a root cause, it's a guess.
- Editing code to observe behavior (printf-debugging the source) when a loop could isolate it.
- Calling a workaround a fix. Workaround = acknowledged, tracked separately, never silently.
- Multiple simultaneous changes while debugging — bisect one variable at a time.

## Escalation

- Loop can't be built after real effort → narrow the symptom: minimize input, find the smallest
  failing case, check environment drift (versions, config, caches) before blaming the code.
- 3 failed fix attempts on one theory → stop, rebuild the loop / question the theory (AGENTS.md
  "change strategy, document attempts").

## Notes

- Source: hermes-agent skills/software-development/systematic-debugging/SKILL.md (MIT, adapted from
  obra/superpowers). Mechanics verified from the repo at /tmp/hermes-agent.
- This workflow pairs with test-driven-development (write the failing test first) and
  plan-before-code (scope before editing).
