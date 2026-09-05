# Memory: two-stage pipeline for DSH memento (omp port)

Sources: omp `prompts/memories/` (`stage_one_system.md`, `consolidation.md`, `read-path.md`),
/etc/nixos/docs/howto/agent-memory-pipeline.md, the `dsh-memento` plugin
(`~/.dsh/profiles/web/node_modules/dsh-memento`), `@deepseek-ai/dsh-skill-filesystem` (SKILL.md
format).

Below are two ready-made prompt files (stage 1 and stage 2) and the integration specification. The prompts
are written for LLM invocation; `{{...}}` are placeholders filled in by the integration layer.

______________________________________________________________________

## 1) memory-extract — stage 1 (extraction)

````markdown
# memory-extract — stage 1: extracting durable knowledge (DSH memento)

You are the first-stage memory extractor for DeepSeek Harness. You receive a rollout — a
completed fragment of agent work: a session/round transcript, the `todo_write` list, tool
results, and (optionally) a compaction summary. You extract only reusable
durable knowledge for the second stage (memory-consolidate). You do not write anything into
memento yourself — you only return JSON.

## Strict output contract
Return strictly JSON and nothing else: no markdown wrapper, no comments, no text before or after.

```json
{
  "rollout_summary": "string",
  "rollout_slug": "string | null",
  "raw_memory": "string"
}
```

## Field semantics
- `rollout_summary` — a compact synopsis (≤ 500 characters) that future runs must remember: what was done, why, and how it ended.
- `rollout_slug` — a short lowercase slug of letters/digits/`_`/`-` (e.g. `nixos-rebuild-oom`) identifying the rollout topic; `null` if there is no topic.
- `raw_memory` — detailed durable blocks with enough context for reuse. Format: a bulleted list of blocks `- [slug] fact/decision/constraint/gotcha/resolved failure`, each block self-contained.

## What to keep (durable signal)
- Environment constraints and invariants (e.g. `--option substitute false`, the ban on edits in excluded domains).
- Decisions made and why exactly this way (tradeoff + choice).
- Reproducible workflows: exact commands, flags, paths, order of steps.
- Gotchas and resolved failures (what already broke and how it was fixed).
- User corrections and preferences that affect future work.

## What to drop (noise)
- Transit chatter, greetings, restating the obvious.
- Low-information noise, intermediate edits without a takeaway.
- Anything that will not be needed in a future session.
- Secrets, tokens, passwords, keys — NEVER.

## Quality rules
- No durable signal → `rollout_summary` and `raw_memory` are empty strings and `rollout_slug` is `null`. Nothing "just in case".
- One topic = one block; do not merge different topics into one paragraph.
- Specificity beats completeness: exact identifiers instead of "somewhere in the config".
- Respect the hard memento budget (the agent track defaults to 4000 characters per layer): save characters, but do not lose reusable context.
- Your output is input for stage 2; do not decide on its behalf what is stale, but tag provenance with the slug.

## Place in the pipeline
You run at the end of a rollout (a completed goal/round/session). The result is passed to
memory-consolidate. Reading from memento and writing to it is done by stage 2 / the integration layer, not by you.
````

______________________________________________________________________

## 2) memory-consolidate — stage 2 (consolidation)

````markdown
# memory-consolidate — stage 2: merging into memento + SKILL.md (DSH)

You are the second-stage memory consolidator for DeepSeek Harness. You merge the corpus of "raw"
memories and stage-1 summaries into long-term memory (memento, user/agent tracks,
user-global/workspace layers) and reusable SKILL.md playbooks. You do not call write tools
yourself — you return a plan document in strict JSON; the integration layer applies it
through the `memory` tool and the skill filesystem.

## Input
- `{{raw_memories}}` — stage-1 raw_memory blocks.
- `{{rollout_summaries}}` — stage-1 summaries.
- `{{memento_snapshot}}` — current memento entries (agent/workspace, user/workspace, user/user-global) with budgets.
- `{{existing_skill_names}}` — names of already installed skills.

## Strict output contract
Return strictly JSON and nothing else: no markdown wrapper, no comments.

```json
{
  "memory_md": "string",
  "memory_summary": "string",
  "skills": [
    {
      "name": "string",
      "description": "string",
      "whenToUse": "string",
      "content": "string",
      "files": [ { "path": "string", "content": "string" } ]
    }
  ]
}
```

## Field semantics
- `memory_md` — the long-term memory document. Structure it with `## <slug>: <topic>` headings; each section is a self-contained heuristic/fact/process context that the integration layer splits into separate memento entries (agent/workspace).
- `memory_summary` — a hint for the prompt timer: ≤ 800 characters, lists the main topics and when to apply them. It lands in agent/workspace as a `[summary] ...` entry.
- `skills` — reusable playbooks. An empty array is allowed.
  - `name` — kebab-case, the `skills/<name>/SKILL.md` directory.
  - `description` — one sentence (≤ 200 characters): the DSH catalog string.
  - `whenToUse` — one sentence: when to load the skill.
  - `content` — the FULL text of `SKILL.md`, including YAML frontmatter:

```yaml
---
name: <name>
description: <description>
whenToUse: <whenToUse>
---
```

    Then the concrete playbook steps.
  - `files` — optional; only files worth keeping long term. `path` is relative to the skill directory (`scripts/…`, `references/…`, `templates/…`), `content` is the full text.

## Consolidation rules
- Merge recurring topics from raw_memories and rollout_summaries; keep useful existing topics from `memento_snapshot`.
- Prune stale content: if an old guideline contradicts the current repository/runtime/user instruction — do NOT include it in the output (the integration layer removes the old entry/skill). Include the corrected version only if it is confirmed.
- Memory is heuristics and process context; the current repository state, runtime output and user instruction are facts and final decisions. On a discrepancy the memory is stale.
- Confidence only after verification in the repository; memory by itself is NEVER evidence.
- Do not include secrets/tokens/passwords.
- Respect memento budgets: by default agent 4000, user 2000 characters per layer. `memory_md` must fit into agent/workspace after the split; if tight — pick the most durable content and consolidate rather than split needlessly.
- Keep user facts (preferences, communication style, "landmines") separate: in `memory_md` mark the section `## user: <topic>`; the integration layer puts it into the user track (user-global or workspace).

## What each skill means
Create a skill only for a recurring successful procedure (workflow) that a future agent must execute step by step. Do not create a skill for a one-off fact — it goes into `memory_md`. A skill name is short, imperative, unique; on a conflict with an existing name either reuse the name and update `content`, or choose a new name.
````

______________________________________________________________________

## 3) Integration specification

### When to run

| Stage | Trigger | Input | Output |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------- |
| memory-extract | end of every completed rollout: goal/round complete, delegated task finished, session closing (incl. after compaction) | session transcript (user/assistant/tool events), `todo_write` history, tool results, optionally a compaction summary | strict JSON (summary/slug/raw_memory); NOT written to memento |
| memory-consolidate | after 3–5 extract results accumulate; or agent/workspace is ≥ ~70% full; or `BUDGET_EXCEEDED` is received; or the working session ends | accumulated `raw_memory` + `rollout_summary`, current `memento_snapshot` (agent/workspace + user layers) with budgets, `existing_skill_names` | plan JSON (memory_md/memory_summary/skills[]) — applied by the integration layer |

Implementation recommendation: stage 1 is a lightweight subagent on goal/round completion (DSH
`dsh-goal`/goal-round driver); stage 2 is a separate step of the integration plugin or a
foreground subagent on a schedule/budget trigger. The exact hook is registered for the harness version; the
prompts themselves do not depend on the hook.

### Mapping of omp artifacts → DSH

| omp                             | DSH memento / skills                                                                                                      |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `rollout_summary` | input only for stage 2; not stored separately |
| `rollout_slug` | provenance prefix in the entry text and in skill files |
| `raw_memory` | stage-2 corpus; standalone durable facts can go directly into agent/workspace |
| `memory_summary` | `memory add` track=agent scope=workspace text=`[summary] <text>`; replaces the previous one by the unique substring `[summary]` |
| `memory_md` (`## topic` sections) | split by headings; each section → `memory add/replace` track=agent scope=workspace text=`<slug>: <topic> — <section>` |
| `memory_md` (`## user:` sections) | track=user; scope=user-global (cross-workspace) or workspace (for the current cwd) |
| `skills[].name` / `content` | write `<skillsRoot>/<name>/SKILL.md`; `name` must match the directory name (kebab-case) |
| `skills[].files` | write `<skillsRoot>/<name>/<path>`; only `SKILL.md` auto-loads, the rest are reference files |
| stale artifacts | absent from the output → the integration layer runs `memory remove` (unique substring) or deletes the skill directory |

### Where to write SKILL.md (dsh-skill-filesystem)

- Workspace playbooks: `<projectRoot>/.dsh/skills/<name>/SKILL.md` (rank 100).
- Cross-workspace playbooks: `<dshHome>/skills/<name>/SKILL.md` (usually `~/.dsh/skills`, rank 400).
- Frontmatter is required: `name` + `description`; `whenToUse` is optional. Only name+description reach the model catalog;
  the body is loaded on demand (`skill` tool or `/name`).

### Write order (integration layer)

1. `memory query` current agent/workspace and user entries + budgets.
1. Remove/replace stale entries by a unique substring (ambiguous → use a longer substring).
1. Add new entries; on `BUDGET_EXCEEDED` — `memory consolidate` (1–20 into one) and repeat.
1. Write/update `SKILL.md`, remove the cleaned-up skill directories.
1. All entries go through the dsh-memento approval gate (`writePolicy: ask|auto|off`); prompts do not
   bypass it.

### Reading rules (adaptation of read-path.md)

1. First `memory_summary` (the `[summary]` entry).
1. Then memory_md entries and `SKILL.md` as needed.
1. Memory = heuristics/process context; repository/runtime/user instruction =
   facts/final decisions.
1. Memory contradicts repo/instruction → it is stale: fix the behavior, then update/regenerate the
   artifact.
1. Confidence only after verification in the repository; memory by itself is NEVER evidence.

### Constraints and safety

- No secrets/tokens/passwords.
- Budgets are hard (by default user 2000, agent 4000 characters per layer); silent truncation is
  forbidden.
- Entries are approval-gated and audited; `writePolicy` is neither seen nor changed by the model.
- Stage-2 output is advisory: the current state of the repository always outranks memory.
