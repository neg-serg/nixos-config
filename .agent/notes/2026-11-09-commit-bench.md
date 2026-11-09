# Commit-message bench: small local tiers, 2026-11-09

Question: which local tier can turn a real diff into a commit message that follows this repository's
conventions, and what does quality cost in wall time? The bench is `llmctl bench commit`
(`modules/llm/llmctl.py`); `llmctl commit` uses the same prompt for day-to-day messages.

## Design

- Nine real commits from this repository, fixed by hash: a one-file package patch (aurora/ffmpeg), a
  subtle Nix setting (registry), a two-file alias repair (btm), a shell script (rollout reports), a
  config-only addition (GTK4 GSettings schemas), a Justfile fix (clean-caches), a layout checker
  (pleamar geometry), a multi-file feature (Samba shares) and a 32-bit packaging change (RCT).
  `git show` is fed without the message; the reply is graded against the commit that was actually
  made.
- Prompt: repo conventions (bracketed scope, imperative subject \<=72 chars, 2-5 sentence body), the
  scope vocabulary from the last 400 subjects, the changed-file list and the raw patch. One-shot
  example on. Temperature 0, `enable_thinking` pinned off, prompt cache off.
- Rubric, 10 points per case: format (2), scope (2), subject token recall (2), body
  presence/recall/grounding (2), no invented paths and body-not-restating- subject (2). Full gold
  message scores 10/10, so the ceiling is calibrated. The mechanical rubric is a ranking signal, not
  ground truth: e.g. every model describes the new guard in `btm-alias` while gold's subject
  emphasises restoring the alias; both are truthful, and the rubric marks the models down for it.

## Results (final prompt, example on, one run per tier)

| model                   | total/90 | avg  | median wall | first call | decode      | out tokens |
| ----------------------- | -------- | ---- | ----------- | ---------- | ----------- | ---------- |
| qwen3.8-27b-abliterated | 81.6     | 9.06 | 4.8 s       | 12.2 s     | 38.5 tok/s  | 113        |
| qwen3.8-27b-bartowski   | 81.2     | 9.02 | 6.0 s       | 14.2 s     | 34.0 tok/s  | 122        |
| qwen3.8-27b-unsloth     | 80.0     | 8.89 | 5.0 s       | 14.4 s     | 39.4 tok/s  | 118        |
| devstral-small-2-24b    | 76.5     | 8.50 | 3.8 s       | 10.1 s     | 51.2 tok/s  | 107        |
| tiny (4B, CPU)          | 75.3     | 8.37 | 17.1 s      | 23.9 s     | 19.1 tok/s  | 144        |
| qwen3-vl-8b-abliterated | 73.3     | 8.14 | 1.5 s       | 7.9 s      | 87.1 tok/s  | 124        |
| gemma4-26b-abliterated  | 70.8     | 7.87 | 1.5 s       | 10.5 s     | 110.4 tok/s | 94         |

"Median wall" is the median over the nine cases after the model is loaded; "first call" includes the
swap/load and is the practical cold-start cost. Decode is llama.cpp's `predicted_per_second`; wall
times were collected with no competing GPU job. `tiny` was served by a standalone CPU llama-server
on :8099 so it would not disturb the GPU runs; llama-swap's `tiny` slot uses the same weights and
flags.

## What moved the score

1. A one-shot example fixed a format failure and was worth ~3 points on qwen3-vl-8b: without it the
   model wrote subject and body on one line for one case and lost the body. Keep the example.
1. The scope vocabulary is useful but its order primed weak models: three different tiers wrote
   `[gui/pleamar]` for the GTK4 theme case, because that is the most frequent scope in the log.
   Rewording the list as "vocabulary, not a suggestion" fixed qwen3-vl's scope on that case without
   dropping the list. Alphabetical order (69.8) and no list (68.4) both scored lower because models
   then invented scopes outside the vocabulary.
1. The 27B tier is consistently best (81.5/81.6 across two prompt versions); devstral and gemma4
   improved by ~2-3 points from the same wording fix.
1. Quant source does not matter for commit writing: abliterated 81.6, bartowski 81.2, unsloth 80.0,
   with decode 38.5/34.0/39.4 tok/s. The spread is inside rubric noise, so the quant choice should
   follow the science/fp benches, not this one.

## Practical default

`llmctl commit` defaults to `--model auto`: keep whatever llama-swap already has resident, else load
`qwen3-vl-8b-abliterated`. That gives either the quality tier at no swap cost, or a ~1.5 s warm
message plus a one-time 8 s load. For the best possible text at ~5-6 s warm, pass
`--model qwen3.8-27b-abliterated` (or `bartowski`); for a GPU-free run, `tiny` at ~17 s is close in
quality to the 8B but does not touch VRAM.

```
llmctl commit                        # git diff HEAD, print message
llmctl commit --staged --verbose
llmctl commit --staged --model qwen3.8-27b-abliterated --apply
llmctl bench commit --models qwen3-vl-8b-abliterated --example
llmctl bench commit --models tiny --show --scopes alpha
```

Run results are JSON under `~/.local/state/llmctl/commit-*.json` (for this session's runs, under
`/tmp/llm-bench-commit/...` because of the agent file sandbox). Every reply is stored with its
rubric notes, wall time, prompt and decode counts, so the ranking can be re-derived or re-judged
without rerunning the models.

## Caveats

- One run per tier, nine cases: totals have a repeat spread of roughly +-2 points (qwen3-vl measured
  72.4-75.3 across prompt variants, tiny 75.3-78.7). Use the ranking for tier selection, not for
  sub-point comparisons.
- Wall times are warm-model medians; llama-swap swaps models on demand, so a real `llmctl commit`
  usually pays the first-call cost unless the tier is already resident. `--model auto` avoids that
  by reusing the resident tier.
- The scope is the weakest part for every small tier. `--scopes none` lets a model pick a
  path-derived scope that is sometimes better than the vocabulary guess, at the cost of more
  invented scopes.
