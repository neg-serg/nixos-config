______________________________________________________________________

## description: Spike — throwaway experiments to validate an idea before a real build (ported from hermes-agent spike, adapted from gsd-build/get-shit-done)

______________________________________________________________________

# Spike

Use when the user wants to **feel out an idea** before committing to a real build — validating
feasibility, comparing approaches, or surfacing unknowns that no amount of research will answer.
Spikes are disposable by design: throw them away once they've paid their debt.

Triggers: "let me try this", "I want to see if X works", "spike this out", "before I commit to Y",
"quick prototype of Z", "is this even possible?", "compare A vs B".

## When NOT to use

- The answer is knowable from docs or reading code — do research, don't build.
- The work is the production path — use plan-before-code instead.
- The idea is already validated — jump straight to implementation.

## Core method

1. **State the question** in one falsifiable sentence: "Does X achieve Y under condition Z?" The
   spike is done when this question has an evidence-backed answer.
1. **Isolate.** Throwaway location (/tmp or a scratch dir), minimal input, smallest possible
   surface. No integration with real config, no commits to the main branch.
1. **Timebox.** Propose a bound (minutes, not hours). If the answer isn't reached, report what WAS
   learned and stop — do not silently expand.
1. **Compare honestly** (when "compare A vs B"): run both against the same inputs, same machine,
   record numbers/outputs side by side. No cherry-picking.
1. **Conclude with a verdict** — Given/When/Then style: "Given X, when Y, then Z (evidence: …)".
   State what the spike did NOT prove as clearly as what it did.
1. **Dispose.** Delete or clearly mark the scratch as throwaway. Do not let spike code leak into the
   real change as "it already works".

## Verdict formats

- Feasible → hand off to plan-before-code with the evidence.
- Not feasible → report the blocker with evidence; propose the alternative.
- Inconclusive → say what's missing and propose the narrowest next experiment.

## Notes

- Source: hermes-agent skills/software-development/spike/SKILL.md (MIT, adapted from
  gsd-build/get-shit-done). Local repo: /tmp/hermes-agent.
- Pairs with debugging.md (a spike often builds the tight loop) and plan-before-code.md (what comes
  after a successful spike).
