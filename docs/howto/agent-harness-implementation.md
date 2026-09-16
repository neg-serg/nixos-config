# Harness features: designs and rollout plan (compiled from subagents)

Summary of the parallel work: DSH integration map (recon) + designs of four feature groups produced
by subagents. Full texts live in `docs/howto/designs/`.

## Key reconnaissance conclusion

DSH web is a Cordis host assembled from patch files; server plugins = fork packages with
`cordis.patch.yml` (a row in the profile), client plugins = browser UI only, `patch.py` = string
edits of compiled bundles (not to be used for logic). The needed hooks already exist: `agent/status`
(idle), `turn/end`, `tools/post-execute` (results), `tools/execute` (argument wrapper),
`compaction/*`, `todo/write`, `goal/change`. The auto-continuation pattern is
`dsh-goal-round-driver` (`agent.followup`). Todo = the last `todo/write` event (last-write-wins).
Memento — the third-party plugin `dsh-memento` (`ctx.provide('memory')`, SQLite
`~/.dsh/dsh-memento/`).

## Designs

| File                                                                       | Contents                                                                                                                                                                                                                                                                                              | Status     |
| -------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| `designs/dsh-recon.md`                                                     | integration map: packages, plugins, events, integration points for all 5 features                                                                                                                                                                                                                     | ✅ ready   |
| `designs/rules-hooks.md`                                                   | 4 small hooks: agent-usage-reminder (S), compaction-todo-preserver (S), rules-injector (M), category-skill-reminder (S–M); all as server plugins in the neg preset; order: usage → todo-preserver → rules → category                                                                                  | ✅ ready   |
| `designs/hashline.md`                                                      | hash-anchored edits: `read_hashline` + `hashline_edit`, xxHash32 → CID (ZPMQVRWSNKTXJBYH), CAS `fs/write-intent`, MVP 1.5–3 days as a client fork plugin; tags in built-in `read` — phase 2 (`dsh-tool-fs` patch)                                                                                     | ✅ ready   |
| `designs/memory-pipeline.md`                                               | two ready prompts (memory-extract, memory-consolidate) + integration with memento: triggers, mapping into tracks/skills, budgets, approval-gate                                                                                                                                                       | ✅ ready   |
| `.agent/prompts/memory-extract.md`, `.agent/prompts/memory-consolidate.md` | ready prompts (RU), extracted from the design                                                                                                                                                                                                                                                         | ✅ in repo |
| `designs/boulder.md`                                                       | boulder: behavioral specification (countdown 2s, backoff 30s×2 max 5, 5-minute pause, stagnation max 3, compaction guard 60s, full "when NOT to inject" list), integration (`packages/dsh-boulder/` in the fork), skeleton: package.json + constants (exact text) + index.ts (host logic) + client.ts | ✅ ready   |

## Rollout status (updated)

All 7 plan items were **implemented** and committed as server plugins in
`modules/user/nix-maid/apps/` (the now-removed `dsh-osm` was the pattern: package.json +
lib/index.js

- ensure + patch-row). Two of them, `dsh-memory-extractor` and `dsh-boulder`, were removed with the
  dsh web GUI in 2026-09 and are marked below:

1. ✅ **dsh-agent-usage-reminder** — `tools/post-execute` + `additionalContexts`.
1. ✅ **dsh-compaction-todo-preserver** — `session/event` compaction/start→end, re-append
   `todo/write`.
1. ✅ **dsh-rules-injector** — `tools/post-execute` on read: `rules/*.md` + root AGENTS.md
   (frontmatter alwaysApply/glob, per-session dedupe).
1. ✅ **dsh-category-skill-reminder** — agent plane (`dsh-liangshen-fork/agent.cordis.yml`), skill
   catalog via `ctx.skills.snapshot`.
1. **dsh-memory-extractor** — *removed 2026-09:* `session/end-seed`/`compaction/end` → draft-extract
   into memento; **TODO**: LLM step (plugins have no model-call service in this DSH build).
1. **dsh-boulder** — *removed 2026-09, design-only now:* `agent/status` idle + todo projection +
   `agent.steer` with CONTINUATION_PROMPT (countdown 2s, backoff 5s×2, max 5, 5-minute pause,
   stagnation 3, compaction guard 60s) + toast-client.
1. ✅ **dsh-hashline** — `read_hashline` + `hashline_edit` (FNV-1a → CID, hash validation, atomic
   write); functionally tested.

Plus: **dsh-debug** — DAP debugging (gdb/lldb-dap/dlv/debugpy/js-debug-adapter, launch/attach,
breakpoints/stepping/inspection/evaluate; tested on gdb). Limitation: gdb 17.2 DAP returns empty
`threads` after attach.

Additions (closing the gaps): dsh-debug `custom_request` (raw DAP requests), dsh-ttsr mental-models
(background knowledge once per session).

Remaining: hashline phase 2 (tags in built-in `read` — `dsh-tool-fs` patch, deferred). The
`vscode-js-debug`/`bun`/`ast-grep` packages are already in systemPackages (in PATH after rebuild,
verified).

## What is already in the repo from this port

- `.agent/workflows/notepads.md` — notepad system
  (learnings/decisions/issues/verification/problems), read before delegating, append after a task,
  pass to all subsequent subagents.
- `agent-guards.md` §6 — exact text of the boulder injection (CONTINUATION_PROMPT) + backoff
  mechanics.
- `agent-memory-pipeline.md` — two-stage memory concept (subagent design — detail).

## Open questions

- Where do the neg-preset fork plugins live (`modules/user/nix-maid/apps/` vs a fork source tree) —
  recon points at server plugins, but the fork source directory for new packages still needs to be
  chosen (for example `packages/dsh/server-plugins/`).
- Whether `dsh-memento` is patched as a third-party plugin in the profile or through a fork — to be
  clarified when implementing item 5.
- boulder: the exact "do not inject while waiting for the user's answer" scenario requires checking
  `agent/inbox`/pending-question, like in omo.
