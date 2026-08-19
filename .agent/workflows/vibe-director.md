______________________________________________________________________

## description: Vibe director — drive several persistent worker subagents (ported from omp vibe)

______________________________________________________________________

# Vibe Director

Run several focused worker subagents in parallel and steer them by name, like omp's vibe mode: each
worker is spawned once, kept alive across turns, and addressed by a stable id.

## Steps

1. **Plan the roster**: decide the workers (e.g. `librarian`, `cleaner`, `verifier`) and what each
   owns. Keep the roster small (2-4); overlapping ownership causes collisions.

1. **Spawn with `subagent` (background)** — one call per worker, each with the full 7-element prompt
   (TASK / EXPECTED OUTCOME / SKILLS / TOOLS / MUST DO / MUST NOT DO / CONTEXT) and a distinctive
   description that doubles as its name.

1. **Collect the ids** returned by the spawn calls — these are the addressable worker ids.

1. **Steer by id**: use `send_message` to give a worker a follow-up (it becomes the next turn of
   that same conversation; the worker's context persists). Do NOT re-spawn for follow-ups.

1. **Coordinate**: when two workers may touch the same files, tell them explicitly who owns what
   (anti-duplication rule from plan-before-code).

1. **Collect and merge**: when workers settle, gather their reports, verify against the repo
   (goal-completion audit rules), and resolve conflicts yourself.

## Notes

- Workers are not replacable mid-flight: if one fails, re-spawn a fresh worker rather than piling
  more work onto a confused one.
- Keep worker prompts self-contained — they do not see this conversation.
- This is the DSH-native version of omp's vibe mode (persistent, addressable worker sessions); no
  harness code needed.
