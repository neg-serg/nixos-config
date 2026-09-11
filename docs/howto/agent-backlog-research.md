# Backlog (collab / browser / computer / vibe / autoresearch): "how to do it" research

Date: 2026-08-20. Research of primary sources + local DSH infrastructure on odin. Five directions
from agent-deferred §11-13; for each — facts, the "how it should be done" pattern, the DSH
implementation, risks, estimate. Conclusions: what to close as covered, what to do next.

## 0. Local baseline (what already exists)

- Local Ollama on odin (ROCm): qwen3:8b-q8_0 (fast), gemma4:12b, qwen3-coder:30b,
  **qwen2.5vl:7b-q8_0 (vision!)** — for understanding screenshots; data never leaves the host.
- DSH: persistent subagents + `send_message` (worker addressability), `dsh-tool-web` (web_search
  only; `fetch: false` on the host — policy), `tools.restrict()` in dsh-tools (narrowing the tool
  scope), multi-session web GUI, `dsh-api-remotes`/`dsh-client-connection`.
- Already ported: vibe-director workflow (omp ln-mode), boulder (todo control), ab-bench.mjs (A/B of
  prompts), code-review.mjs (git diff → model).

## 1. collab — live collaboration

**Facts**

- Basic collab already exists in DSH: web GUI (multiple sessions), subagents (persistent,
  addressable), `send_message` — that is "director → workers" on live sessions.
- The official `deepseek-harness-agentchat` (npm 0.1.0) is a bridge to an EXTERNAL AgentChat service
  (OpenClaw dialect, outbound WS, `uin` accounts, QQ-style, Chinese stack). Irrelevant for us:
  external service + Chinese interface (the user does not read Chinese).
- `dsh-api-remotes` / `dsh-client-connection` — the DSH client-server connection layer.

**How to do it (if ever)**

- Reference relay architecture: AgentWorkforce/relay ARCHITECTURE.md.
- E2E (AES) over WS for multi-user; session isolation by scope (like worker ids in vibe).
- Do NOT reinvent the transport: DSH already has client-connection; build on top of it.

**Conclusion**: do not start. Local collaboration (sessions + subagents) is covered; the external IM
bridge (agentchat) is a foreign stack; relay/AES is a separate project with no explicit request.

## 2. browser — browser automation

> **Dropped (2026-08)**: the implementation (dsh-browser + headless chromium) was removed from the
> config — CDP is not used, see AGENTS.md (Automation: desktop only). The section is kept as
> research history.

**Facts**

- `dsh-tool-web` provides search only; `fetch: false` on the host — security policy.
- No browser tools in the profile.

**"How it should be done" pattern** (browser-use: "Leaving Playwright for CDP")

- Direct CDP instead of Playwright: headless Chromium (`--remote-debugging-port` or pipe) + a CDP
  client (Runtime/Page/Input/Emulation domains). Fewer dependencies, closer to the metal.
- Page screenshot → vision model (local qwen2.5vl:7b) for understanding → actions via the Input
  domain (click/type/scroll) and the Page domain (navigate/extract DOM).

**Implementation in DSH**

1. systemd-user service `browser-cdp`: `chromium --headless=new --remote-debugging-port=9222` (from
   nixpkgs; chromium sandbox enabled, NOT `--no-sandbox`).
1. DSH tool `browser`: navigate / screenshot / extract / click / type — with a domain allowlist,
   timeouts; read-only by default (navigate+screenshot+extract), actions are explicit calls.
1. Vision step: screenshot → local VL model (qwen2.5vl:7b); do not store screenshots.

**Risks**: chromium updates in nixpkgs, memory (headless ~300-500MB), DOM fragility. **Estimate**:
medium complexity; the next candidate after vibe/autoresearch.

## 3. computer — desktop control

**Facts**

- odin: Wayland + Hyprland. No desktop primitives in DSH.

**"How it should be done" pattern** — `computer-use-linux` (Rust MCP server/CLI, crates.io + npm
wrapper `@agent-sh/computer-use-linux`, prebuilt binaries; extracted from Codex Desktop Linux):

- **Semantic selectors via AT-SPI** (role/name/text/states); pixels only as a fallback
  (canvas/games). More private and more reliable than OCR on screenshots.
- Wayland works: pointer via `org.freedesktop.portal.RemoteDesktop` + `ydotool` (uinput) as a
  deterministic fallback; screenshots via portal (GNOME Shell DBus / Screenshot).
- **Compositor-aware window targeting**: Hyprland `hyprctl` (our WM!), KWin, i3, X11/EWMH.
- `doctor` — JSON readiness report (platform, portals, AT-SPI, windows, input).

**Implementation in DSH**

1. Install the binary (check availability in nixpkgs at implementation time; otherwise a wrapper
   package with prebuilt binaries).
1. DSH tool `desktop`: doctor / list_windows / screenshot / click / type / scroll — selectors by
   role/name/text; vision layer for screenshots — local VL model.
1. Security: tools run only on an explicit agent call (no background ones), approval for actions,
   screenshots are not persisted.

**Risks**: Wayland portals/permissions (RemoteDesktop requires a user session), the ydotool service,
availability in nixpkgs. **Estimate**: medium; expected to work on Hyprland (hyprctl + ydotool).

## 4. vibe-runtime

**Fact** (omp docs/vibe-mode.md): vibe mode = the top session becomes the DIRECTOR: its tools are
narrowed to read/todo/worker-control; workers do the searching/editing/running; the director
verifies worker claims by reading files. Workers are persistent, addressable, scoped to their owner;
`/vibe` switches the mode.

**Conclusion**: in DSH this is ALREADY covered at the workflow + infrastructure level:

- `vibe-director` workflow (port of ln-mode) — director + persistent workers.
- Persistent subagents + `send_message` = addressability and verification by reading.
- `tools.restrict()` (dsh-tools) = narrowing the director tools (read/todo + subagent tools) —
  implemented in a preset, no new plugin.

**Recommendation**: close as "covered by workflow"; optionally a vibe preset with restrict.

## 5. autoresearch-runtime

**Fact**: the `ab-bench.mjs` prototype works (presets × tasks + pairwise jury; demo 3:0).

**How to do it (runtime)**

1. Task set from real sessions: `export-session.mjs` (JSONL → HTML) → distill tasks, plus a manually
   maintained tasks.json.
1. Background run: `systemd-run --user` launches ab-bench on the test set; reports accumulate in a
   directory (e.g. `~/.local/share/ab-bench/` or `/zero/ai/ab-reports`).
1. Compare presets by accumulated statistics (wins, time, answer lengths).
1. Optionally: DSH tool `ab_bench` (run + show the latest report).

**Estimate**: small; the next quick step — background runner + report accumulation.

## Summary: order and decisions

| Direction            | Decision                                                                                                                                                                                           | Estimate |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| vibe-runtime         | ✅ covered (workflow + subagents); optional preset with restrict                                                                                                                                   | small    |
| autoresearch-runtime | do: background runner + reports on top of ab-bench.mjs                                                                                                                                             | small    |
| browser              | ~~do: browser-cdp (CDP) + tool + vision~~ — dropped (2026-08): CDP is not used                                                                                                                     | —        |
| computer             | ✅ **extended (2026-08-20, v0.2)**: native layers (hyprctl/grim/wtype, zero-daemon) + CUL MCP (click/drag/scroll/state, per-call) + AT-SPI (apps; org.a11y.Bus enabled in NixOS); 36 live tests ✅ | medium   |
| collab               | do not start (covered locally; agentchat — foreign stack; relay — a project)                                                                                                                       | —        |

Security everywhere: explicit calls, approval, allowlist, local VL models (screenshots do not leave
the host). All features rely on the free GPU/local models — without external APIs.

Tool choice: `desktop` — for human-like GUI interaction (real windows, AT-SPI, local vision);
`browser` (CDP) removed (2026-08) — programmatic page access is not needed. Fixed in AGENTS.md
(Automation: desktop only, CDP not used).
