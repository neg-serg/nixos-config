# Niche omp features: port notes (vibe / cleanse / export / secrets / tan)

Five small omp features that do not warrant a separate plugin but are worth recording as ideas and
stubs for DSH. Source: omp 17.3.4 (`/nix/store/.../omp-17.3.4/share/omp/src`).

## 1. vibe — persistent worker sessions

`src/vibe/` (runtime.ts, state.ts): "vibe" mode in which the director drives several persistent
worker agents ("CLI"): each is spawned once (keep-alive), lives between turns (TTL park +
JSONL revive), and is addressed by name. Tools: vibe-spawn/list/send/kill/wait.

**Port to DSH**: we already have background subagents and `send_message` — the same mechanism.
Only "park/revive" (long-lived addressable sessions) is missing — it can be shaped as a
"vibe-director" workflow on top of the existing subagents, without harness code.

## 2. cleanse — codebase cleanup

`src/cleanse/`: the command runs discovery agents that find checkers (lint, tests,
typecheck), then interactively selects and runs them, fixes what it found, and commits.

**Port to DSH**: a workflow in `.agent/workflows/` — "codebase cleanse": (1) discover checkers (just
lint / check / osh -n / statix / deadnix / shellcheck), (2) run them, (3) fix per feature, (4)
commit. In essence already covered by `agent-recipes.md` + the repo lint chain; a separate
workflow can be assembled if desired.

## 3. export — exporting/sharing sessions

`src/export/` (share.ts, custom-share.ts, html/, ttsr.ts): export a session to an HTML page for
sharing, custom exports, export of TTSR rules.

**Port to DSH**: DSH sessions are in JSONL and there is a Workspace browser; HTML sharing is a
small client/command feature. Defer (low priority).

## 4. secrets — placeholder scanning of keys

`src/secrets/` (placeholder-scan.ts, obfuscator.ts, message-transform.ts): detects 43-character API
keys (and other placeholders) in output, replaces them with `***`/on-the-fly obfuscation, and stores
a per-install key in XDG state. Protection against leaking secrets into prompts/logs.

**Port to DSH**: very useful — keys can show up in DSH logs and transcripts. Options: (a) a plugin
hook on `tools/result`/`assistant/message` with regex masking of 43-character tokens; (b) at minimum
add a rule to AGENTS.md: "never output tokens/keys in full, mask them". Do (b) right away,
put (a) in the backlog.

## 5. tan — context switch

`prompts/system/tan-context-switch.md`: quick context/project switcher, reminder that "the active
project is a different one, do not mix them up". Idea: an explicit workspace-change marker.

**Port to DSH**: rule in AGENTS.md for working across several repositories: when switching projects,
re-read its AGENTS.md and explicitly record the switch. Can be added as a single line in the
scope section.

## Summary

- Right away (already/now): secrets rule in AGENTS.md (masking), tan rule, cleanse workflow.
- Later: vibe-director on top of subagents, HTML session export, key-masking plugin.

