# Port omp / oh-my-opencode → DSH: final summary

What came out of the whole effort: 18 DSH server plugins (dsh-browser with headless chromium was
removed in 2026-08; dsh-boulder, dsh-lsp and dsh-memory-extractor were removed with the web GUI in
2026-09), docs, workflows, prompts, plus a check on the live host after `nixos-rebuild switch`.

## 1. Plugins (all in `modules/user/nix-maid/apps/`; the live profile is the TUI one — the web profile was removed in 2026-09)

| Plugin                        | What it does                                                                                                              | Test                                                                    | Commit                                 |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- | -------------------------------------- |
| dsh-debug                     | DAP debugging: gdb/lldb-dap/dlv/debugpy/js-debug, launch/attach, breakpoints, stepping, inspect, evaluate, custom_request | ✅ gdb launch→bp→continue→stack→vars→terminate; attach; custom_request  | 50213471, 968ab65a, 8f08714b           |
| dsh-hashline                  | read_hashline + hashline_edit (LINE#ID tags, refusal on hash mismatch)                                                    | ✅ gdb test file, read/edit/mismatch                                    | ba3105b4                               |
| dsh-read-tags                 | LINE#ID anchors in the built-in read output (phase 2; hash as in dsh-hashline)                                            | ✅ tags match read_hashline 4/4                                         | 04472acb                               |
| dsh-boulder                   | todo-continuation: idle + open todos → steer with CONTINUATION_PROMPT (+ toast client)                                    | removed 2026-09; was live (fired in sessions)                           | 3995f5f1, 027a80ee                     |
| dsh-rules-injector            | injects rules/\*.md + AGENTS.md on file touch (alwaysApply/glob, dedup)                                                   | ✅                                                                      | dcbe0df7                               |
| dsh-agent-usage-reminder      | hints to delegate after runs of manual searches                                                                           | ✅ live                                                                 | 4c56685f                               |
| dsh-category-skill-reminder   | reminder to delegate + skills (agent plane)                                                                               | ✅ live                                                                 | 6170dcf7, 376a1c7f                     |
| dsh-compaction-todo-preserver | todos survive compaction (compaction/start→end)                                                                           | ✅                                                                      | b1eca24a                               |
| dsh-memory-extractor          | session-end extract into memento: draft transcript + LLM step via local Ollama (JSON per memory-extract.md)               | removed 2026-09; was draft + LLM `[extract]` (qwen3:8b-q8_0) + fallback | 9145ff98, a20260e9, 699c47c0, 39614204 |
| dsh-secrets-masker            | masks keys in tool results (43-char, sk-, ghp\_, ...)                                                                     | ✅ unit                                                                 | 1861761a                               |
| dsh-lsp                       | LSP: hover/definition/references/rename/code_actions (rust-analyzer, clangd, pyright, tsserver)                           | removed 2026-09; was pyright hover/def/refs/rename; clangd: def+hover   | c1a70484                               |
| dsh-eval                      | persistent Python/Bun kernels (state between calls, reset)                                                                | ✅ py: x=41→42; bun: z=5→10                                             | a9828f46                               |
| dsh-ttsr                      | correction rules on output + mental models (agent plane)                                                                  | ✅ TODO rule; mental 1×/session                                         | e55c340e, 8f08714b                     |
| dsh-advisor                   | peer-shadow advisor: local Ollama on agent/pre-step, one remark (non-blocking)                                            | ✅ request drift caught (2 injections in test)                          | 361057a2                               |
| dsh-hub                       | supervised processes: start/send/wait/stop/list                                                                           | ✅ cat/sleep                                                            | 5b5a0b85                               |
| dsh-ast-grep                  | structural search/rewrite via ast-grep (1-based positions)                                                                | ✅ real binary: search/rewrite                                          | 715c6e5e, 51a37f10                     |
| dsh-checkpoint                | checkpoint/rewind (soft): exploration replaced by a report                                                                | ✅                                                                      | 163735c6                               |
| dsh-desktop                   | desktop: doctor/windows/screenshot (grim) + click/type/scroll (MCP computer-use-linux)                                    | ✅ doctor+windows+grim on Hyprland                                      | 23670c12                               |

## 2. Docs and workflows

- `AGENTS.md`: evidence-first, ask, todos, goal-audit, web-search etiquette, secrets hygiene, tan.
- `docs/howto/`: agent-guards (9 guards), agent-advisor, agent-memory-pipeline, subagent-contract,
  agent-categories, agent-port-research, agent-harness-features, agent-harness-implementation,
  agent-misc-ports, agent-deferred (plan + closed gaps + honest leftovers), designs/ (5 designs).
- `.agent/workflows/`: plan-before-code, delegate-task, security-scan, notepads, vibe-director,
  codebase-cleanse, autolearn; `.agent/prompts/`: memory-extract, memory-consolidate;
  `.agent/scripts/export-session.mjs` (JSONL.zstd → HTML); `.agent/scripts/ab-bench.mjs` (A/B bench
  for prompts: presets × tasks + pairwise judging via local Ollama);
  `.agent/scripts/code-review.mjs` (git diff → local model → remarks); `.agent/scripts/ab-run.mjs` +
  `.agent/bench/` (runtime A/B: task set, reports in `~/.local/share/ab-bench/`);
  `agent-backlog-research.md` (plan: collab/browser/computer/vibe).

## 3. Verified on the live host (after the rebuild)

Historical check (2026-08/09): dsh-boulder, dsh-lsp and dsh-memory-extractor were removed with the
web GUI in 2026-09 — see §1; the results below are from this check, not from the current tree.

- The old `dsh.service` (web GUI) was removed in 2026-09 — there is no unit to check; the TUI runs
  in the terminal.
- **bun** and **ast-grep** are now on the system PATH (`/run/current-system/sw/bin/`).
- Real tests after the rebuild: `ast_grep` search/rewrite on a rust fixture ✅; `eval` python
  (val=6.283) and bun (z=5→10, let/const/class persist between calls: a=42) ✅; `lsp` pyright
  (hover/def/refs/rename) ✅ and clangd (with compile_commands.json: definition+hover ✅);
  **js-debug** (socket transport: launch+terminate ✅; breakpoint/step — even with a bp set before
  launch on a live script, it gives no stopped/threads in this setup — a documented limitation); the
  rules-injector logic (inject+dedup ✅), compaction-todo-preserver (re-append ✅), memory-extractor
  (draft ✅).
- Fired live: boulder (todo continuations), category-skill-reminder, TTSR injections.
- LLM bench for memory-extractor (odin, RX 9070 XT 16GB): qwen3:8b-q8_0 26s/52 tok/s — the default;
  gemma4:12b 47s; deepseek-r1:14b 48s; qwen3dot5 loops; qwen3.5:27b does not fit.
- Real usage (2026-08-20): desktop screenshot→vision (real windows recognized) ✅; browser
  (dsh-browser / headless chromium) removed in 2026-08 — CDP is not used (AGENTS.md hard rule);
  downscale the screenshot to ~1280px before vision (VL context 4096 tokens).

## 4. What remains (honestly)

- Restart the TUI (`dsh --profile tui`) to pick up the latest edits (js-debug resolve,
  mental-models); the old `systemctl --user restart dsh` went away with the web GUI (2026-09).
- js-debug (JS/TS debugging): launch/terminate verified (socket transport); breakpoint/step give no
  stopped/threads even with a breakpoint set before launch on a live script (setTimeout 6s) — a
  documented limitation of the nixpkgs adapter build (it expects a full VS Code configuration:
  runtimeArgs/sourceMapPause/...; out of the box it only gives launch/terminate).
- Not verified live (needs a real session/toolchain): lsp rust-analyzer (rustup in a sandbox without
  a default toolchain; on the host the binary is on PATH — a project with Cargo.toml + toolchain is
  needed); boulder toast (a GUI element, cannot be checked headless). Both plugins were later
  removed — see §1. Logic of the rest — see §3.
- Not closed (in agent-deferred): mid-stream TTSR, collab/autoresearch/vibe-runtime/computer.

## 5. Lessons

- cordis requires `inject` to access services (ctx.tools/ctx.memory) — without it, it throws on
  access.
- The binary name in nixpkgs ≠ the name in VS Code (js-debug vs js-debug-adapter); `sg` is taken by
  shadow-utils.
- gdb DAP answers launch only after configurationDone; threads after attach are empty (gdb 17.2).
- node:vm does not persist let/const between calls — use var/assignment for the kernel.
- pyright requires workspaceFolders in initialize, otherwise it gives «/<default workspace root>».
- clangd without compile_commands.json is almost mute (standalone file); with a compile db it works
  (def+hover ✅).
- js-debug from nixpkgs is a headless adapter: without a full VS Code configuration it gives no
  threads/stopped; launch/terminate work.
