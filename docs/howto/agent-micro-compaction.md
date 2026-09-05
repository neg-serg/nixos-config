# Micro-compaction: continuous compaction design for DSH

Design port from **NousResearch/hermes-agent** (docs/micro-compaction.md, MIT). Closes the
`preemptive-compaction` item from the agent-harness-features.md backlog: instead of "preemptive
compaction before the limit" — continuous amortized compaction after each turn.

## Problem

Ordinary compaction is a batch: the context crosses the threshold → the session stops, a large
middle chunk is summarized in a single call, then it resumes. Downsides: one visible pause, one
large bill at a random moment, occupancy sawtooths up to the threshold.

## Idea

After each completed turn, fold **one oldest unabsorbed exchange** into the running summary. The
work is the same, but in pieces — no pause, the bill is spread out, context stays low.

## Exchange boundaries

- An exchange = an assistant message + all of its tool results and follow-up iterations, up to the
  next user message. In tool-heavy work that is where most tokens live (file reads/command output).
- The **whole turn** is taken, not an individual tool result: valid role alternation is preserved —
  the summary marker has the assistant role, the turn is bounded by user messages on both sides.
- **User messages are never compacted.** The pass starts from an assistant message and goes
  past user messages. User instructions remain verbatim for the whole session: assistant narrative
  ("read the file, ran the command") survives summarization, user intent does not; paraphrasing
  "use the retry helper, don't add a new one" is a direct path to the agent doing the opposite
  six turns later.

## Mechanics

1. Hook on turn end (in DSH — session/event of the "turn done" type or agent/pre-step, see the
   seam below).
1. If there is an unabsorbed exchange: call summarization (local model, see below), replace the
   exchange in the transcript with a single assistant-role summary message.
1. Defrag: when the running summary exceeds the threshold (defrag_threshold_tokens, default 2000),
   re-summarize it instead of growing forever.
1. Summarizer failure: leave the transcript alone, count errors; **3 consecutive failures → the
   cursor moves on** (otherwise one bad exchange is retried on every turn forever); the skipped one
   will be picked up by the next batch compaction.
1. Persistence: archive the old lines and insert the compact set atomically; if the DB step failed —
   log it, the session resume will double-load the summary until the next batch (in DSH — JSONL
   sessions: mark replaced lines as absorbed so the append-only flush skips them).

## Config

```yaml
micro_compact: true                     # opt-in (off by default)
micro_compact_every_n_turns: 1          # pass cadence: 1 = after every turn (max reclaim,
                                        #   1 prefix-cache break per turn); 5 = rarer, fewer breaks
micro_compact_defrag_threshold_tokens: 2000  # threshold for re-summarizing the summary
```

The cadence counter advances per turn, not per successful pass — a turn without an absorbable
exchange still advances the cadence and does not stall the mechanics. Values \<1 clamp to 1.

## Summarization model

- A **small fast non-reasoning instruct model** fits. Hermes observations: a local 7B 4-bit model
  (MLX) ~31s per pass; a large reasoning model is noticeably slower (thinking tokens on
  summarization) and usually no better.
- DSH on odin already has a local Ollama: qwen3:8b-q8_0 (52 tok/s, memory-extractor benchmark) —
  the default for summarization; gemma4:12b as an option.
- If passes are too slow (descending order of effect): smaller/faster model → less loaded host →
  disable micro-compaction and fall back to batch.

## What it buys (metrics)

Micro-compaction is NOT token savings and NOT a speedup; measuring it in tokens undersells it. Two
values:

1. **The pause is amortized** — the same summarization, but in small chunks after turns instead of
   one stall in the middle of a session.
1. **Context lives longer** — occupancy stays low instead of sawtoothing up to the threshold; the
   session runs noticeably longer (often indefinitely) before a batch becomes necessary.

## Cost

Each pass breaks the prefix cache once (frozen prefix + inserted summary). So the feature is
opt-in, and the cadence is a deliberate choice: on a deep cache discount (expensive provider) choose 5,
on local models — 1.

## Seam in DSH (checked against dsh plugins)

| Layer                                                           | What exists in DSH                                                                  |
| --------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| End-of-turn hook                                                | session/event (KNOWN_SESSION_EVENT_TYPES) or agent/pre-step — like in                |
| dsh-boulder / dsh-ttsr                                          |                                                                                     |
| Transcript write                                                | ctx / steer mechanics (agent-plane), dsh-compaction-todo-preserver as an             |
| example of "surviving compaction"                               |                                                                                     |
| Local summarization                                             | Ollama API (http://127.0.0.1:11434/api/chat) — the pattern from                     |
| dsh-memory-extractor                                            |                                                                                     |
| Config                                                          | patch-row in cordis.patch.yml (like memory-extractor: endpoint/model/everyNTurns/   |
| defragThreshold/enabled)                                        |                                                                                     |
| Test                                                            | mock session: 5 turns, feature enabled → oldest exchange replaced with a summary;   |
| user messages untouched; 3 failures → cursor moved on; disabled → nothing changes    |                                                                                     |

## Relationship to existing functionality

- No conflict with dsh-compaction-todo-preserver: todo is stored separately and re-injected;
  micro-compaction compresses the transcript and leaves the todo list alone.
- Supplements (does not replace) DSH's built-in batch limit: the batch remains the safety net,
  micro-compaction pushes back when it would fire.
- Double-compaction risk (why preemptive-compaction was deferred): at cadence ≥2 the pass happens
  after a turn, the built-in compactor fires only by threshold — there is no overlap window if the
  micro pass marks replaced lines and the batch leaves them alone.

## Status

Design. Implementation is a separate task (dsh-micro-compaction plugin per the agent-deferred.md §0
recipe: package.json + lib/index.js + .nix + test). Priority: medium — local models are cheap, but
the feature is more complex than the small hooks (absorption registry + persistence + defrag).
