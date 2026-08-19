______________________________________________________________________

## description: Delegate a subagent task with the 7-element template (ported from oh-my-opencode)

______________________________________________________________________

# Delegate Task

Before delegating to a subagent, write the prompt with all 7 elements — clear and specific. The
subagent does not see the parent conversation: the prompt must be standalone.

## The 7 Elements

Canonical oh-my-opencode form is **6 sections** (TASK / EXPECTED OUTCOME / REQUIRED TOOLS / MUST DO
/ MUST NOT DO / CONTEXT); REQUIRED SKILLS rides separately via `load_skills`. Use all 7 when skills
matter, 6 otherwise.

1. **TASK** — single objective: what needs to be done.
1. **EXPECTED OUTCOME** — the deliverable.
1. **REQUIRED SKILLS** — skills to load (e.g. via load_skills), if any (optional 7th).
1. **REQUIRED TOOLS** — tool whitelist, if constrained.
1. **MUST DO** — constraints that must hold.
1. **MUST NOT DO** — things that must never happen.
1. **CONTEXT** — file paths, existing patterns, reference material.

## Bad example

> "Fix this"

## Good example

> **TASK**: Fix mobile layout breaking issue in the navbar component **CONTEXT**:
> `packages/web/components/Navbar.tsx`, Tailwind CSS **MUST DO**: Change flex-direction at `md:`
> breakpoint **MUST NOT DO**: Modify existing desktop layout **EXPECTED**: Buttons align vertically
> on mobile

## Rules

- Include the 7 elements whenever the delegated task has real ambiguity or risk.
- After the run, feed learnings (successes/failures/gotchas) into the next delegation
  (oh-my-opencode "wisdom accumulation" idea).
