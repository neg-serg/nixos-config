# Implementation Plan for Deferred Features (lsp / eval / checkpoint / TTSR / and others)

A full-fledged plan for implementing them in this repository on our own (without "strong models").
Each feature is a separate server plugin following the already-proven recipe; the order is by
value/risk.

## 0. Plugin recipe (reference — 9 already done)

Each plugin = 4 files + a test:

- `modules/user/nix-maid/apps/dsh-<name>/package.json` — name/type=module/main=lib/index.js/exports;
- `modules/user/nix-maid/apps/dsh-<name>/lib/index.js` — `export const name` + `apply(ctx)`; when
  services are used, `export const inject = [...]` is MANDATORY (lesson: ctx.tools/ctx.memory);
- `modules/user/nix-maid/apps/dsh-<name>/` — the plugin bundle (package.json + lib/index.js). The
  web-profile caretaker modules were removed with the web GUI in 2026-09; the TUI profile seeds the
  bundle through `dsh-tui-ru.nix` (`tuiPlugins` / `seed`), so no per-plugin `.nix` is needed;
- `modules/user/nix-maid/apps/default.nix` — add `n != "dsh-<name>"` to the exclude list;
- functional test: run node against the bundle from `~/.dsh/profiles/tui/node_modules/` (or a copy),
  with an `apply({tools:{register}, effect})` mock, verifying a real scenario (like hashline/debug).

Pre-commit checks: `node --check`, `nix-instantiate --parse`,
`bash scripts/dev/check-all-syntax.sh`, `just fmt`, pre-commit lint (--no-verify only for foreign
ghost files). Activation:
`rm -rf ~/.dsh/profiles/web/node_modules/dsh-<name> && systemctl --user restart dsh`.

## 1. dsh-lsp — symbolic code navigation (priority #1)

**Goal**: a `lsp` tool — rename, references, definition, hover, code actions, diagnostics;
positional operations (`file`+`line`+`symbol`), `apply:false` for previewing edits.

**Architecture**: LSP client over stdio (JSON-RPC, Content-Length — like DapClient in dsh-debug,
only server-initiated: `initialize` → `initialized` → `textDocument/didOpen`); a per-language server
pool; position mapping (line/column ↔ offset); starting the server from a config (language →
command).

**Key DSH APIs**: `ctx.tools.register(defineTool({...}))` + `inject: ['tools']`; use
exec.agent.session.header.cwd for the project root (as in dsh-debug/hashline).

**Steps**: 1) adapter config (rust-analyzer, clangd, pyright, tsserver, gopls — by what is present
on the host); 2) LSP client (request/response + notifications); 3) the `lsp` tool with ops: hover,
definition, references, rename (apply:false|true), code_actions, diagnostics; 4) lifecycle
(shutdown/exit, timeouts); 5) test: open a real repo file (rust/python),
definition/references/rename preview.

**Acceptance**: rename works on a real file with preview and apply; references return all call
sites; no process leaks (the server is killed together with the plugin). Risks: LSP dialects,
position mapping, memory.

## 2. dsh-eval — persistent Python/Bun kernel

**Goal**: an `eval` tool — persistent kernel: state survives across calls and subagents; incremental
cells (imports → define → test → use); reset on crash; `parallel(thunks)` inside a cell.

**Architecture**: a long-lived process (python3 -i / bun -e loop) owned by the plugin; JSON command
protocol; kernel registry (session → kernel), idle-timeout, budget (output limit), reset on crash
(if the process died — restart with a clean state and an explicit message).

**Steps**: 1) python kernel (stdin/stdout JSON loop); 2) bun kernel (equivalent); 3) the `eval` tool
(code, reset, parallel in a cell); 4) registry + idle-timeout; 5) test: define a variable → use it
in the next call → reset → confirm the namespace is clean.

**Acceptance**: state survives calls; a kernel crash does not hang the plugin; limits fire. Risks:
isolation (do not give the kernel access to secrets beyond what is needed), process leaks.

## 3. checkpoint / rewind — rolling back the exploration context

**Goal**: `checkpoint` puts a marker before exploration; `rewind` rolls the context back to the
marker, replacing the intermediate calls with a short report (token savings).

**Architecture**: two tools + a snapshot store (session → marker). First, research: how DSH stores
history (dsh-session JSONL, events) — where to hook in. Minimal version (soft rewind): checkpoint
saves a short summary of the exploration; rewind returns it as a synthetic user instruction "forget
the intermediate stuff, work from this summary" — WITHOUT real history surgery.

**Acceptance**: after rewind the agent continues from the summary; intermediate calls are not
re-read. Risks: interfering with the session history — v1 is soft rewind only (an instruction).

## 4. TTSR / hindsight — rules on the stream

**Goal**: regex rules (condition/scope/body) on the agent output stream interrupt and inject a
correction; mental-models — background summaries in the prompt.

**Architecture**: rule store (config rules), a hook on `assistant/message` (check presence in
KNOWN_SESSION_EVENT_TYPES or agent/pre-step) + injection via agent.steer (like boulder);
mental-models — systemPrompt.section with background text (the concept is already in agent-guards.md
§9).

**Steps**: 1) rule format (YAML: condition regex, scope, body — from omfg-user/TTSR); 2) matching
engine; 3) injection; 4) test: a rule on "TODO: fix later" in the output; 5) mental-models v1 — a
static systemPrompt.section loaded from a file.

**Acceptance**: the rule fires and injects a correction; a narrow scope does not catch extraneous
output; the mental-model is visible in the prompt as background knowledge. Risks: finding out
exactly where DSH offers a hook on the stream — verify first.

## 5. dsh-ast-grep — structural search/edit

**Goal**: an `ast_grep` tool wrapping the ast-grep binary (sg from nixpkgs): search by AST pattern,
rewrite (the -r flag), highlighting, glob filters. One language per call; `$NAME` captures.

**Steps**: 1) add `pkgs.ast-grep` to systemPackages (like vscode-js-debug); 2) the tool: search (sg
JSON output), run (rewrite with interactivity disabled), 3) test: find a function call in the repo,
rewrite preview.

**Acceptance**: a pattern with captures finds the expected nodes; rewrite does not touch files
without matches. Risks: sg flags changed between versions — check `sg --help` on the target version.

## 6. dsh-hub — supervised long-running processes

**Goal**: a `hub` tool (op:start/list/stop) for REPLs, watchers, dev servers: the process lives
between calls, output is collected, the result is delivered on completion/timeout.

**Architecture**: a process registry (session → {proc, output buffer, status}); op:start (command,
cwd, async), op:list (statuses), op:stop, op:wait (waits for completion/timeout). In parallel with
dsh jobs, but inside the agent session and with access to the buffer.

**Acceptance**: a server/REPL starts, survives several calls, stops without zombie processes. Risks:
orphan processes when dsh crashes — clean them up in ctx.effect shutdown.

## 7. autolearn — automatic SKILL.md promotion — ✅ DONE (workflow .agent/workflows/autolearn.md)

**Goal**: automatically create/improve SKILL.md from recurring successful techniques (omp learn /
manage_skill). Implementable as a WORKFLOW (no plugin): after solving a task the agent itself
decides whether the technique is worth recording and creates a skill from a template.

**Steps**: 1) SKILL.md template (frontmatter name/description/whenToUse — as in memory); 2) the
autolearn.md workflow: criteria (the procedure is repeatable, it solved a problem), path
(.dsh/skills/<name>/SKILL.md), rules (do not touch user skills, no duplicates); 3) wire it to
memory-extract.

**Acceptance**: the workflow is in the repo; the criteria are clear. Risks: catalog pollution — cap
the number.

## 8. export — HTML sharing of sessions — ✅ DONE (minimal exporter .agent/scripts/export-session.mjs)

**Goal**: a command/plugin that exports the current session to standalone HTML (like omp
export/html). Medium priority; first research: how DSH stores the session (JSONL) and whether a
ready-made renderer exists (web-ui). Minimal version: a bash script/command that assembles the JSONL
into HTML with minimal styling.

## 9. snapcompact — snapshot compaction — 🟡 FEASIBLE (research 2026-08-20)

Research of dsh-compaction in the store found the extension point: **CompactionEngine — an abstract
service; providers decide when to compact, subclassing it** ("providers decide when to compact and
replace a history range with one summary node by subclassing CompactionEngine"). Replacing a range
with one summary node + the `compactCheckpointSource` marker (kind=plugin,
plugin=COMPACT_CHECKPOINT_MARKER) — that is exactly the snapshot frame. The events
`compaction/start|end|summary` carry shadowedRange/shadowedSeqs/shadowedTokenCount — enough for a
snapshot summary. So a safe v1 is visible: the `dsh-snapcompact` plugin = a CompactionEngine
subclass that writes a snapshot frame before the regular compaction and cuts the history; the risk
of breaking sessions is removed by the fact that the engine already knows how to replace a range
with one node.

**Goal**: compaction with context snapshots (omp snapcompact-\*). Plan: 1) ✅ API research
(CompactionEngine subclass seam + compactCheckpointSource + summary fields); 2) prototype
`dsh-snapcompact` (subclass, snapshot frame, trigger policy); 3) test on a live session. Priority:
medium (after harness polish items).

## 10. stt / tts — ✅ COVERED by the existing stack (speech.nix), omp port NOT needed

The repo already has a full speech stack (`modules/media/audio/speech.nix`): piper-tts (TTS, :8001),
whisper-cpp Vulkan (STT, :8002), chatterbox-tts (ROCm), cosyvoice/moshi in
`/zero/ai/speech/engines`. From omp stt/tts only the UX part is relevant (endpointer,
streaming-player) — as a reference, not a port.

**Goal**: ASR (dictation into a session) and TTS (voicing answers) with Russian models — relevant to
the speech requirement. Take omp infrastructure (src/stt, src/tts: worker, endpointer,
streaming-player, vocalizer) as a model, but implement separately on sherpa-onnx (nixpkgs). Plan: 1)
check sherpa-onnx in nixpkgs; 2) CLI prototype (wav → text; text → wav) outside DSH; 3) plugin:
stt/tts tools or web-client integration; 4) Russian models (download, licenses). Priority: medium
(after lsp/eval).

## 11-13. collab / autoresearch / browser / computer

- collab (live sessions, relay, AES): very high complexity, a niche — do NOT start without an
  explicit request; if ever — as a separate project, not a plugin.
- ~~autoresearch~~ — **done**: `.agent/scripts/ab-bench.mjs` (presets × tasks → pairwise jury via
  local Ollama) + `.agent/scripts/ab-run.mjs` (runtime: corpus in `.agent/bench/`, reports in
  `~/.local/share/ab-bench/`, summary.csv). Run over 5 tasks: detailed 3:2 terse — depends on task
  type.
- ~~local code review~~ — **done**: `.agent/scripts/code-review.mjs` (git diff → local model →
  comments; test on the ab-bench diff: 8 comments).
- ~~browser~~ — **implemented and removed (2026-08)**: dsh-browser + headless chromium removed from
  the config — CDP is not used (AGENTS.md hard rule), automation only through desktop.
- ~~computer~~ — **extended (2026-08-20, dsh-desktop v0.2)**: computer-use-linux v0.4.9 prebuilt +
  patchelf; **layers**: native zero-daemon (hyprctl windows/ focused/focus/move/resize + grim
  screenshot + wtype type/press_key), CUL MCP per-call
  (click/drag/scroll/state/set_value/perform_action; spawn→kill, nothing stays resident), AT-SPI
  apps (list_apps; org.a11y.Bus enabled in NixOS: dbus activation + user unit at-spi-dbus-bus, see
  dsh-desktop.nix). All 16 actions + backend auto/native/cul; tests: 29 mock + 36 live (node
  test.mjs [--live]). Resources: native — instant processes, CUL — 7.7 MB binary only for the
  duration of the call; the a11y bus comes up on demand.

## Recommended execution order

1. dsh-lsp (maximum benefit) → 2. dsh-eval → 3. TTSR (research the stream hook first) → 4. dsh-hub →
   5\. dsh-ast-grep (fast, awaits a rebuild for sg) → 6. checkpoint/rewind (soft) → 7. autolearn
   (workflow) → 8. export → 9. stt/tts → 10. snapcompact (after the research).

Each feature is a separate commit `[dev/ai] Add dsh-<name> ...` with a functional test.

## Closed gaps (additions to the ports)

- **dsh-debug `custom_request`** — raw DAP requests (`command` + `arguments`) through the active
  session; test: `custom_request threads` returned the real gdb threads. Commit `8f08714b`.
- **dsh-ttsr mental-models** — background knowledge (`config.mentalModel` or `lib/mental-model.md`)
  is injected ONCE per session as a `<mental-model>` note (not a command). Test: the first injection
  is present, the second is not. Commit `8f08714b`.

## Still UNclosed (honestly, with reasons)

- ~~advisor runtime~~ — **CLOSED**: the `dsh-advisor` plugin (agent-plane, agent/pre-step) once
  every `interval` steps asynchronously asks the local Ollama (`qwen3:8b-q8_0`) about the recent
  steps and injects one short remark at the next pre-step (does not block the loop; silence filter,
  inFlight guard, max 5 per session; config `{endpoint, model, interval, timeoutMs, enabled}`).
  Test: it catches drift from the request ("Code changes contradict the original request").
- **mid-stream TTSR** — verified (2026-08-20): dsh-ttsr works on `agent/pre-step` (inject between
  steps), and the LLM stream is governed by AbortSignal — the plugin can cancel the current request
  (`aborted`), but cannot insert an edit into an already-running stream. Full mid-stream is
  impossible without forking `dsh-llm`/the agent loop; the current version (inject at the next
  pre-step + abort on a hard violation) is the maximum without a fork.
- ~~hashline tags in the builtin `read`~~ — **CLOSED (phase 2)**: the `dsh-read-tags` plugin via
  `tools/post-execute` rewrites the content of the builtin `read` into `N#ID| text` (hash identical
  to dsh-hashline, verified 4/4), without forking `dsh-tool-fs`; composition with the spill policy
  is preserved (the listener does not prepend).
- ~~eval bun `let`/`const`~~ — **CLOSED**: on bun 1.3.13 and node v24 top-level `let`/`const`/
  `class` persist between kernel calls (verified: `a=42`, `c=10`, `P=7`); a repeated `let a = ...` →
  SyntaxError, as in a REPL.
- ~~LLM-step memory-extractor~~ — **CLOSED**: the plugin calls the LOCAL Ollama
  (`http://127.0.0.1:11434/api/chat`) on session/end-seed/compaction/end; JSON per memory-extract.md
  is written as `[extract]`, on failure/no signal it falls back to `[draft-extract]`. Config
  `{endpoint, model, timeoutMs, enabled}`; the model is switched in the plugin's patch-row config
  (`cordis.patch.yml` → `config.model`). **Bench 2026-08-20 (odin, RX 9070 XT 16GB)**:
  `qwen3:8b-q8_0` 26s/52 tok/s — default; `gemma4:12b` 47s; `deepseek-r1-distill-qwen:14b` 48s;
  `qwen3dot5:latest` 6s, but loops/does not produce JSON — removed from the default; `qwen3.5:27b`
  does not fit into 16GB VRAM (>300s).
- **collab / vibe runtime / autoresearch-runtime / computer** — research "how to":
  `docs/howto/agent-backlog-research.md` (vibe is covered by a workflow; autoresearch-runtime is
  small; computer is medium; browser removed (2026-08, CDP not used); collab — do not start).
  hub-peer- IRC — backlog (scope/security).

## Non-plugin deferred problems (odin config)

- **fastfetch: the animated WebP logo (blizzard) is rendered TOO SMALL** when launching
  `fastfetch --logo-type kitty-icat --logo <blizzard-*.webp>` — the picture comes out small, which
  is unsatisfactory. The size needs to be increased via `--logo-width` / `--logo-height` (or
  `logo.width/height` in the config) so the skull with the blizzard takes up a noticeable share next
  to the info column.
