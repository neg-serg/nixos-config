# Port hermes-agent (Nous Research) and other similar projects → DSH

Research on **NousResearch/hermes-agent** (MIT) and a cross-check against what was already ported
from omp / oh-my-opencode. What hermes adds, what is already covered, what to port. Sources — the
local clone `/tmp/hermes-agent` (commit 27562ad, ~190 MB) + hermes-agent.nousresearch.com.

## What is hermes-agent

A personal AI agent that runs one core on top of the CLI, messenger gateways (Telegram, Discord,
Slack and ~20 platforms), a TUI and an Electron desktop. It is extended with **plugins and skills**,
not by core growth. Two project axioms (from AGENTS.md):

- **Per-conversation prompt caching is sacred** — the prefix cache survives the entire session; any
  mutation of past context or a mid-session system-prompt rebuild breaks the cache and multiplies
  cost. The only exception is context compression.
- **Core = narrow waist** — every core tool is sent in every API call, so the bar for a new core
  tool is high; a new capability is a CLI command + a skill, a service-gated tool, or a plugin.

## What is new (not covered by the omp/omo ports)

### 1. Micro-compaction — continuous amortized compaction (docs/micro-compaction.md)

The most valuable find. Ordinary compaction is a batch: threshold crossed → the session stops, the
middle is summarized with one call, one big pause and one big bill. Micro-compaction pays the same
bill **in installments**: after each completed turn it folds **one oldest unabsorbed exchange**
(assistant+tools, up to the next user message) into a running summary.

Key properties:

- **User messages are never compacted** — a turn starts with an assistant message and flows past
  user messages; user instructions stay verbatim for the entire session. Rationale: the assistant's
  narrative (“read the file, ran the command”) survives summarization, while the user's intent does
  not.
- A full turn (rather than a single tool result) preserves a valid role alternation: the summary
  marker has an assistant role, and the turn is bounded by user messages on both sides.
- **Defrag**: when the running summary exceeds the threshold
  (`micro_compact_defrag_threshold_tokens`, default 2000), it is re-summarized instead of growing
  forever.
- Config: `micro_compact: true`, `micro_compact_every_n_turns: 1|5|…` (frequency of cache pauses),
  the defrag threshold. Opt-in, because each pass breaks the prefix cache once.
- Summarizer failure: the transcript stays untouched, the error counter increments; **3 failures in
  a row → the cursor moves on** (otherwise one bad exchange would be retried forever); what was
  skipped is picked up by the next batch.
- Model choice: a small, fast, non-reasoning instruct model (7B MLX, ~31s per pass) beats a large
  reasoning model for summarization.
- Metrics: not token savings, but (1) the pause is amortized, (2) the context lives longer
  (occupancy stays low instead of sawing up to the threshold).

**Port to DSH**: this is a ready-made design for the deferred `preemptive-compaction`
(agent-harness-features.md). Documented separately as `agent-micro-compaction.md`, with mechanics
for a DSH plugin (a hook on turn completion, a registry of “unabsorbed” exchanges, a local
summarization model — qwen3:8b is already installed).

### 2. Prompt assembly: three tiers + cache stability (website/docs/developer-guide/prompt-assembly.md)

The system prompt is assembled from three tiers in strict order (stable → context → volatile):

1. **stable** — identity (SOUL.md), tool/model guidance, skills prompt, environment/platform;
1. **context** — caller-supplied system_message + project context files (`.hermes.md` / `HERMES.md`
   / `AGENTS.md` / `CLAUDE.md` / `.cursorrules`);
1. **volatile** — MEMORY.md snapshot, USER.md snapshot, external memory provider, timestamp.

Ephemeral additions (HERMES_EPHEMERAL_SYSTEM_PROMPT, prefill) are **not part of the cached prefix**.
The developer rule: do not edit prompt_builder.py — change the inputs instead: SOUL.md, MEMORY.md,
project files, skills.

**Port to DSH**: the “stable prefix + volatile tail” principle and “rules via files, not via plugin
edits” — record it in AGENTS.md / a doc as a design principle (we already have dsh-rules-injector
and dsh-memory-extractor — they map onto tiers 2–3 without mutating the prefix).

### 3. Memory tool: MEMORY.md + USER.md (tools/memory_tool.py)

Two bounded folders: **MEMORY.md** (agent notes: environment facts, conventions, tool quirks) and
**USER.md** (what the agent knows about the user: preferences, style, expectations). Design:

- Both files are injected into the system prompt as a **frozen snapshot** at session start.
- Mid-session writes are persisted to disk immediately (durable) but **do not change the system
  prompt** — the prefix cache is preserved; the snapshot refreshes in the next session.
- The record separator is §; records may be multiline; limits are in characters (not tokens).
- A single `memory` tool with actions add/replace/remove; replace/remove by a short unique
  substring.
- Behavioral guidance lives in the tool's schema description, not in the prompt.

**Port to DSH**: all of this is **already implemented** as dsh-memento (user/agent tracks, layers,
substring match, budgets, frozen snapshot at session start) + dsh-memory-extractor. Note the parity
in a doc — hermes confirms the design choice. New: the “USER.md as a separate track” idea already
exists; the § separator and the character-based limits are implementation details that can be
adopted into the memento plugin.

### 4. Todo tool: caps + re-injection after compaction (tools/todo_tool.py)

One `todo` tool with a `todos` parameter (pass it → write; omit it → read); every call returns the
full list. Caps: MAX_TODO_CONTENT_CHARS=4000 per item, MAX_TODO_ITEMS=256; tool result ≤512 KB. The
list is **re-injected after context compression** (a stable header distinguishes the synthetic
string from a real one). No system-prompt mutation.

**Port to DSH**: todo_write already exists; adopt the caps (4000 chars per item) and the
re-injection after compaction (we have dsh-compaction-todo-preserver — compare with the hermes
approach “todo is stored in a message, not in state”).

### 5. Skills: the SKILL.md contract (skills/ + hermes-agent-skill-authoring)

82 SKILL.md files in the repo. Frontmatter format (the validator's hard rules):

- `name` — lowercase-hyphens, ≤64 characters (MAX_NAME_LENGTH);
- `description` — **≤60 characters**, one sentence, no marketing words (powerful/comprehensive/…), a
  capability statement; the system skill index truncates at 57 characters + “...”, so the trigger
  must fit into that window; with `:` inside — quotes, otherwise the YAML breaks;
- `version` — semver, new skills start at 0.1.0;
- `author`, `license`, `platforms: [linux, macos, windows]`;
- `metadata.hermes.tags` + `related_skills`.

**Port to DSH**: the skill-authoring contract — in `agent-skill-authoring.md` (we already have
skills in the session; a uniform ≤60-character description format improves discoverability).

### 6. “Iron law” skills (obra/superpowers adaptations)

- **systematic-debugging**: Iron Law — `NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST`; the
  Feedback Loop Rule — before reading code, create/find a **tight** loop (a command that is red on
  the symptom and green on the fix), not “doesn't crash”. → ported as
  `.agent/workflows/debugging.md`.
- **test-driven-development**: Iron Law — `NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST`;
  RED-GREEN-REFACTOR; “if you haven't seen the test red, you don't know it tests what you think”.
  Exceptions (prototypes, generated code, configs) — only after asking the user.
- **requesting-code-review**: pre-commit pipeline — diff → security scan → quality gates → an
  independent reviewer subagent → auto-fix loop; the principle “No agent should verify its own
  work”. We have code-review.mjs + the security-scan workflow; adopt the “independent reviewer”
  step.
- **simplify-code**: parallel cleanup by 4 reviewers (reuse / quality / efficiency / altitude), one
  review delay instead of four. → an extension of code-review.mjs.
- **spike**: one-off experiments to validate an idea before production; disposable by design. →
  ported as `.agent/workflows/spike.md`.
- **plan**: a plan in a markdown file `.hermes/plans/YYYY-MM-DD_HHMMSS-<slug>.md`, no execution;
  read-only inspection allowed. We have plan-before-code.md — parity.
- **session-librarian**: organizing the session library by prompts (find/rename/archive/prune),
  “show the plan first, then touch anything”. → an idea for DSH (we have recall +
  export-session.mjs).
- **dogfood**: systematic QA of web applications via a browser toolset with evidence. → maps onto
  desktop (AGENTS.md “desktop only, CDP is not used”; dsh-browser removed 2026-08).

### 7. Engineering lessons

- **Context switch guard** (hermes_cli/context_switch_guard.py): warns when switching models within
  a session to a noticeably smaller context — the next turn triggers preflight compaction. → an idea
  for dsh-mode / a hook on model switch.
- **Bounded response reads** (agent/bounded_response.py): reading the error body of a streaming
  response with a byte cap and a **hard wall-clock deadline via a daemon thread** (httpx reads block
  inside the C socket; checking between chunks does not interrupt a hung server). → a lesson for any
  DSH network tool.
- **Kanban multi-gateway** (docs/kanban/multi-gateway.md): single-dispatcher posture — only one
  gateway owns the dispatcher, an atomic claim of events against worker races. → a big feature, not
  ported now (DSH has no gateway aggregator).
- **Cron jobs** (cron/jobs.py): jobs.json + output/{job_id}/{ts}.md, cross-process advisory lock
  (fcntl/msvcrt). → our systemd timers cover this; partial parity.

## Cross-check with the omp/omo ports (already present, do not duplicate)

| hermes idea                                   | Already in the repo                                |
| --------------------------------------------- | -------------------------------------------------- |
| MEMORY.md/USER.md, frozen snapshot, substring | dsh-memento + agent-memory-pipeline.md             |
| Memory extract → consolidate                  | dsh-memory-extractor + .agent/prompts/memory-\*.md |
| Todo re-injection after compaction            | dsh-compaction-todo-preserver                      |
| Plan skill                                    | plan-before-code.md                                |
| Rules via project files                       | dsh-rules-injector                                 |
| Skills/categories                             | dsh-category-skill-reminder + agent-categories.md  |
| Code review before commit                     | code-review.mjs + security-scan workflow           |
| Delegating to subagents                       | delegate-task.md                                   |
| “Desktop over CDP”                            | AGENTS.md (Automation) + dsh-desktop               |
| Harmful/recurring patterns                    | agent-guards.md (9 guards)                         |

## What we are porting (this round)

1. `docs/howto/agent-port-hermes.md` — this document (the map).
1. `docs/howto/agent-micro-compaction.md` — micro-compaction design for DSH (closes
   preemptive-compaction from the backlog).
1. `.agent/workflows/debugging.md` — the Iron Law of debugging (systematic-debugging).
1. `.agent/workflows/spike.md` — one-off experiments.
1. `docs/howto/agent-skill-authoring.md` — the SKILL.md contract.
1. Updates: index.md, agent-harness-features.md (preemptive-compaction status), AGENTS.md (the “root
   cause first” rule).

## Still unread (honestly)

- Full texts of all 82 skills (the key 10 read + the authoring contract).
- hermes kanban/cron/dashboard internals (large features, not being ported now — did not dig in).
- Gateway/session documentation (~18k lines of run.py) — not needed for the ports.
- omp modes/\*, ~50 files of system/ and ~45 tools/ — recorded earlier in agent-port-research.md.
