# Memory: two-stage pipeline (ported from omp)

omp `prompts/memories/`: stage 1 extracts durable knowledge from the session rollout, stage 2 merges
it into long-term memory + playbook skills. Direct analogy with dsh-memento.

## Stage 1 — extraction (stage_one_system.md)

Strict JSON, nothing else:

```json
{ "rollout_summary": "string", "rollout_slug": "string | null", "raw_memory": "string" }
```

- `rollout_summary`: compact synopsis that future runs should remember.
- `rollout_slug`: short lowercase slug (letters/digits/\_), or null.
- `raw_memory`: detailed durable blocks — enough context for reuse.
- No durable signal → empty strings and null. Noise is discarded; nothing is kept "just in case".
- Keep: constraints, decisions, workflows, pitfalls, resolved failures.
- Discard: transient chatter, low-information noise.

## Stage 2 — consolidation (consolidation.md)

Strict JSON: `memory_md`, `memory_summary`, `skills[]`.

- `memory_md`: long-term memory document.
- `memory_summary`: hint on a prompt timer.
- `skills[]`: reusable playbooks; each = `skills/<name>/SKILL.md` (+ optionally
  scripts/templates/examples). Remove outdated ones (prune) so artifacts do not pile up.

## Read rules (read-path.md)

1. First `memory_summary`.
1. Then `MEMORY.md` and `skills/<name>/SKILL.md` as needed.
1. Memory = heuristics and process context; current repo state, runtime output, and the user
   instruction = facts/final decisions.
1. Memory contradicts repo/instruction → memory is outdated; fix the behavior and update the
   artifact.
1. Confidence only after checking the repo; memory alone is NEVER proof.

## Mapping onto dsh-memento

- `memory_md` ≈ agent-track records (workspace); `memory_summary` ≈ session memory snapshot.
- `skills[]` ≈ the DSH SKILL catalog: repeatedly successful session techniques can be auto-promoted
  into SKILL.md playbooks.
- Pipeline = two prompts (extractor/consolidator) + session-completion hooks; the memento budget
  limit is the natural consolidation bound.
