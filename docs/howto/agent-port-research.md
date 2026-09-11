# Agent prompts: omp and oh-my-opencode research — full survey

A supplement to the already-ported pieces (AGENTS.md sections, docs/howto/agent-guards.md,
.agent/workflows/plan-before-code.md, .agent/workflows/delegate-task.md). Here — what was mined
during the deep dive and how it changes the port plan.

## Sources

- **omp 17.3.4** — local: /nix/store/6f6a8cbpqzilf5lv4y6zd0gpkkm5y0mk-omp-17.3.4/share/omp/src (read
  directly: advisor/, memories/, bench/, security/, personalities, the base system prompt, subagent
  prompts, the goal machine, ~10 tool contracts, 9 agent prompts).
- **oh-my-openagent (oh-my-opencode)** — cloned: /tmp/omo-repo (52 MB, dev branch):
  packages/prompts-core/prompts/ (atlas/, prometheus/, ultrawork/, mode/),
  packages/omo-opencode/src/agents/, src/hooks/ (46 hooks), .agents/skills/ + .opencode/skills/
  (SKILL.md), packages/omo-senpi/skills/ulw-plan/.
- **mintlify docs** (canonical md pages): /tmp/mintlify-md/ — 20 pages: all agents, tools
  (hashline-edit, delegate-task, overview), hooks, skills, tmux, mcps, comment-checker,
  introduction.

## omp — findings beyond what is already ported

### 1. Advisor pattern (peer-shadow) — the most underrated

advisor/system.md + advise-tool.md + active-repo-watchdog.md: a dedicated advisor model watches the
agent's incremental transcript (thoughts included) and sends ONE short, concrete remark through
advise_tool — only when something is actually important. What it does:

- challenges premature done, shallow verification, missed reasoning;
- flags drift from the user's request immediately;
- prevents rabbit holes and baked-in edge cases;
- does NOT repeat what the agent already knows (type errors, LSP diagnostics, failed tests);
- read-only by default (read/grep/glob), extended via WATCHDOG.yml;
- has a completeness section: verify first, then raise the issue. Port: a ready scenario for a DSH
  “overseer” subagent or a prompt block for long tasks.

### 2. Two-stage memory (extract → consolidate into SKILL.md playbooks)

memories/stage_one_system.md: a strict JSON is extracted from a “rollout” — rollout_summary,
rollout_slug, raw_memory; no durable signal → empty strings (noise is discarded).
memories/consolidation.md: stage two merges the corpora into memory_md (long-term memory),
memory_summary (a hint for the prompt timer) and skills[] (reusable playbooks, each =
skills/<name>/SKILL.md

- optionally scripts/templates/examples). memories/read-path.md: memory is heuristics and process
  context; the current repo state, runtime output and the user's instruction are facts; “memory
  alone is NEVER proof”. Port: a direct analogy with dsh-memento; the summary + playbooks-as-skills
  format is worth adopting.

### 3. Security pipeline

security/scan-request.md: scanning = running an immutable plan (repo/kind/revisions/include/exclude,
plan-fingerprint) → scope inventory → delegating non-overlapping assignments to a security-reviewer
via task → reconciling the results → one security_publish with findings, honest coverage and the
final report. Port: a template for the gavel/plugin_vet pairing in DSH.

### 4. subagent-system-prompt (omp)

Structure: Role → Context → Plan (the assignment wins on conflict; do NOT re-read the plan from
disk) → Coop (isolated worktree, “never touch files outside the tree”, irc peers via hub: ask the
file owner first, short messages, await only when genuinely stuck) → Completion (no todo narration
or progress updates; only a terminal yield with a result or incremental sections of type: string[]).
Port: a ready template for DSH subagents.

### 5. Misc

- bench/cache-prefix\*.md — a namespace for the prompt cache (a narrow topic, not critical).
- modes/ — modes (print-mode, interactive-mode, ultrathink, turn-budget, loop-limit, ...) — not read
  in detail (see “What is still unread”).

## oh-my-opencode — key findings

### 1. Disciplinary agents and their real prompts

- Sisyphus (orchestrator): todo-driven workflow, Intent Gate (intent classification), strategic
  delegation, parallel execution; after 3 failures in a row — a strategy change, documenting the
  attempts; completion criterion: todos done + lsp_diagnostics clean
  - the build passes + the original request is fully closed.
- Hephaestus (deep worker): “Senior Staff Engineer. You do not guess. You verify. You do not stop
  early. You complete.” — a goal, not a recipe.
- Prometheus (planner): plan mode is sticky (“do X” = “plan X”); execution only in a separate worker
  session via /start-work; all the logic lives in the ulw-plan skill.
- ulw-plan skill: explore-first, “ask few sharp questions — or none”; output = ONE decision-complete
  plan that the worker executes without a single clarification; approval gate (waits for an explicit
  ok); plan-gate: metis/momus reviews are allowed only when a plan file with review_required exists;
  optional advisory lanes architect/ultrabrain (read-only, TASK/ DELIVERABLE/SCOPE/VERIFY/STOP WHEN,
  “claims to verify, not decisions”).
- Metis (gap analysis before planning): intent classification (refactor/feature/bugfix/unknown)
  decides the strategy; MUST-lists like “Define Must NOT Have section (AI over-engineering
  prevention)”, “Record all user decisions in Key Decisions”, “Flag assumptions explicitly”.
- Momus (plan reviewer): approval bias, blocks only verifiable defects (files exist, tasks do not
  contradict each other, QA scenarios are concrete, ~80% clear = executable).
- Oracle: a read-only consultant on architecture/debugging (the AmpCode pattern).
- Atlas (todo orchestrator): Anti-Duplication Rule, 6-Section Prompt Structure (MANDATORY),
  AUTO-CONTINUE POLICY (strict), Parallel Delegation — DEFAULT, NOT OPTIONAL, verify personally
  after every delegation, the notepad system (learnings/decisions/issues/verification/problems),
  Boulder-Complete Nudge.
- Sisyphus-Junior: the executor; the model depends on the category (quick→haiku, deep→codex,
  artistry→gemini, etc.); cannot delegate; must close the todos.

### 2. The exact boulder-injection text (todo-continuation-enforcer)

From hooks/todo-continuation-enforcer/constants.ts (CONTINUATION_PROMPT):

```
[system-directive todo_continuation]
Incomplete tasks remain in your todo list. Continue working on the next pending task.
- Proceed without asking for permission
- Mark each task complete when finished
- Do not stop until all tasks are done
- If you believe all work is already complete, the system is questioning your completion claim.
  Critically re-examine each todo item from a skeptical perspective, verify the work was actually
  done correctly, and update the todo list accordingly.
```

Mechanics: a session.idle event → 2s countdown (toast 900ms, grace 500ms, 3s abort window) →
injection; exponential backoff: base 30s, ×2 per failure, max 5 in a row, then a 5-minute pause;
cooldown 5s; stagnation detection (max 3). Separate guards: compaction-guard (60s), token-limit,
pending-question detection (do not inject while waiting for the user's answer), parent-wake-race.

### 3. hashline-edit — a harness feature, not a prompt

On read, every line gets a {line}#{hash} tag (CID alphabet ZPMQVRWSNKTXJBYH, 2 characters); edits
reference the tags; on a hash mismatch the edit is rejected BEFORE corruption; there are
replace/append/prepend operations, autocorrect on line shifts, errors: hash mismatch, invalid
reference, overlapping ranges. Claimed effect (per README): Grok Code Fast edit success 6.7% →
68.3%.

### 4. Categories and skills

- Categories: quick, deep, ultrabrain, artistry, visual-engineering, writing, unspecified-low/high;
  category → model fallback chain; the category-skill-reminder hook reminds one to load the skills
  for the category.
- SKILL.md: YAML frontmatter (name, description with triggers, metadata); 4 discovery levels
  (project
  > opencode > user > builtin); skill-embedded MCP is isolated with the key sessionID:skill:server.
- hyperplan: 5 “hostile” members (unspecified-low/high, deep, ultrabrain, artistry) through
  team-mode, cross-criticism, surviving insights → to the plan agent; hard preconditions (team-mode
  on, lead role).
- security-research: 3 vulnerability hunters + 2 PoC engineers in parallel, severity by actual
  exploitability.
- ulw-plan — see above; git-master (atomic commits), frontend (design-first UI), playwright (browser
  automation) — “bundle” skills of instructions + MCP.

### 5. Hooks: 46 of them, 3 tiers

Core 37 (Session 23 / Tool Guard 10 / Transform 4), Continuation 7 (boulder sessions, background
tasks), Skill 2 (category-skill-reminder, auto-slash-command). The most valuable:
todo-continuation-enforcer, atlas (master of boulder sessions), compaction-todo-preserver,
rules-injector, preemptive-compaction, edit/json-error-recovery, comment-checker,
notepad-write-guard, plan-format-validator, agent-usage-reminder, keyword-detector,
unstable-agent-babysitter, delegate-task-retry, task-resume-info.

### 6. ultrawork: guarantee protocols

ABSOLUTE CERTAINTY PROTOCOL, Scenario Contract before implementation, manual QA and TDD — MANDATORY,
Verification Anti-Patterns (BLOCKING), Reviewer Gate, Durable Notepad (survives context loss):
Ultrawork Notepad → Plan / Scenarios / Now / Todo / Findings (file:line) / Learnings.

## Port plan revision

Already ported (previous session): evidence-first reasoning, ask default-to-action, todo contract,
goal-completion audit, 9 agent guards, plan-before-code, delegate-task (7 items), categories.

Refinements to the existing pieces:

- delegate-task.md: in Atlas/Sisyphus there are officially 6 sections (TASK/EXPECTED
  OUTCOME/REQUIRED TOOLS/ MUST DO/MUST NOT DO/CONTEXT); REQUIRED SKILLS comes separately via
  load_skills — mark the 7th item as optional.
- agent-guards.md §6: replace the retelling with the exact omo CONTINUATION_PROMPT text + the
  mechanics (backoff 30s×2, max 5, 5-minute pause; do not inject while waiting for the user's
  answer).

New candidates (priority order):

1. Advisor pattern (omp) — an “advisor on top of the agent”, 1 short remark, completeness-first.
1. Two-stage memory extract→consolidate→SKILL.md (omp) — a recommendation for memento.
1. The omp subagent template (Role/Context/Plan/Coop/Completion + the yield protocol).
1. ulw-plan: a decision-complete plan + approval gate + plan-gate for reviewers — strengthen
   plan-before-code.md.
1. Atlas: anti-duplication, parallel delegation by default, verify personally.
1. Security pipeline (omp scan-coordinator → reviewer → publish).
1. hashline-edit — record it as a harness feature (not a prompt), with a separate research.
1. Small hook ideas: category-skill-reminder, agent-usage-reminder, compaction-todo-preserver.

## What is still unread (honestly)

- omp modes/\* in detail; ~50 files of omp system/ and ~45 tools/ (lists obtained; the subagents
  launched for condensation came back with a ready status and no delivered reports — the material
  was collected directly).
- Full texts of atlas/default.md (497 pages), ultrawork/default.md (339 pages), the prompt bodies of
  metis/momus/oracle/explore/librarian from TS (key fragments extracted, not everything).
- docs/guide/agent-model-matching.md, docs/guide/team-mode.md (passed to a subagent; the key ideas
  are covered from orchestration.md and mintlify).
