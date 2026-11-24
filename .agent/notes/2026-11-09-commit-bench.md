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

## 2026-11-11: a dedicated 4B writer

The 8B Qwen3-VL was the fast fallback only because it was the smallest general tier on the card; it
is a vision model and this lane has no images. Four 4B candidates were measured on the same nine
diffs, each served standalone on the 9070 XT (Vulkan, 32k, q8_0 KV), temperature 0, thinking pinned
off per request, example on, prompt cache off, one model at a time:

| model                               | total/90 | median wall | decode      | weights |
| ----------------------------------- | -------- | ----------- | ----------- | ------- |
| qwen3.8-4b (empero distill, Q4_K_M) | **76.9** | 1.3 s       | 114-130 t/s | 2.8 GB  |
| qwen3.5-4b-instruct (Q4_K_M)        | 76.3     | 1.2 s       | 127-131 t/s | 2.7 GB  |
| qwen3-vl-8b-abliterated (re-run)    | 73.9     | 1.7 s       | 88-97 t/s   | 5.0 GB  |
| git-commit-splitter-qwen3-4b Q4_K_M | 70.5     | 0.8 s       | 136-151 t/s | 2.5 GB  |
| qwen3-4b-instruct-2507 (Q4_K_M)     | 70.2     | 1.1 s       | 143-151 t/s | 2.5 GB  |
| falcon-h1-3b (in-fleet)             | 64.8     | 2.6 s       | 46-110 t/s  | 3.4 GB  |

qwen3.8-4b and qwen3.5-4b are inside the +-2 repeat spread of each other, so family broke the tie:
the writer is a distillation of the same Qwen3.8 teacher the `next` tier runs, which keeps the
wording of the 27B. The fine-tune trained on commit messages did not transfer — it invented scopes
(`[lib/package-checks]`, `[utils/ansi]`) and lost 5 points on `btm-alias` alone. Its 0.8 s wall is
real (short replies), but a wrong scope is a wrong message.

The `--split` plan survives the 4B: a scratch repository with four changed files and three unrelated
mechanisms came back as one valid two-group JSON array on the first call (a dropped or invented path
gets a repair round, and a bad plan aborts before any commit).

What the tier costs: 2.8 GB of weights, ~3.1 GiB of VRAM next to a Steam desktop, ~127 tok/s decode.
Thinking is off in the slot (`--reasoning off`): the distill carries its teacher's chain of thought,
and a caller that cannot read `reasoning_content` would wait through thoughts it never sees.

## Practical default

Since 2026-11-24 the writer is the 27B (see the last section): `llmctl commit` defaults to
`--model auto`, which reuses a resident 27B (abliterated, bartowski, unsloth or the vision slot) and
otherwise loads `qwen3.8-27b-abliterated` (the `commit` slot) — a ~5 s warm message plus a ~12 s
cold load. The 4B is one flag away for the cheap case; before that date a cold fleet got the 4B by
default.

```
llmctl commit                        # git diff HEAD, message + commit
llmctl commit --dry-run              # print the message only
llmctl commit --all                  # include new (untracked) files
llmctl commit --staged --verbose     # commit the index
llmctl commit --model commit-4b      # the fast 4B writer, ~1 s
llmctl bench commit --models qwen3.8-27b-abliterated,qwen3.8-4b --example
llmctl bench commit --models qwen3.8-4b --show --scopes alpha
```

From the repository root, `just commit` wraps the same call (arguments pass through, so
`just commit --all` and `just commit --dry-run` work); it uses the repo copy of `llmctl.py`, so the
command is current even before the next system switch.

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

## 2026-11-24: the 27B becomes the default writer

`llmctl commit` used to load the 4B for a cold fleet; the 27B was the "quality pick" only when it
happened to be resident. The default moved to `qwen3.8-27b-abliterated` (the `commit` alias):
message prose first, load time second. `--model auto` still reuses a resident 27B (any of the three
quants, or the vision slot, which carries the same weights), but no longer reuses a resident 4B —
that is the quality the default just moved away from. `--model commit-4b` names it when a cheap
message is wanted.

Re-measured on the same nine diffs (example on, scopes freq, temperature 0, one model resident):

| model                   | total/90 | median wall | decode      | weights |
| ----------------------- | -------- | ----------- | ----------- | ------- |
| qwen3.8-27b-abliterated | **82.6** | ~5.5 s      | 35-41 t/s   | 11 GB   |
| qwen3.8-4b              | 76.9     | 1.3 s       | 114-130 t/s | 2.8 GB  |
| inkling-2-mini          | 77.6     | 30-100 s    | 6.7 t/s     | 11.7 GB |

Inkling-2-Mini was the candidate worth measuring (26B MoE, 13/13 chemistry): it beats the 4B on the
rubric but takes 30-100 s per message — its decode collapses to 6.7 t/s on this prompt — so commit
messages are not its lane. The 27B's price is the cold load (~12 s) and the whole 16 GB card: it
evicts whatever is resident, so committing next to a game stays `--model commit-4b`.

The rubric moves between runs (81.2 -> 81.6 -> 82.6 for the 27B across prompt and fleet changes);
the ordering against the 4B and Inkling did not. Under the agent file sandbox the run prints its
totals but cannot write `~/.local/state/llmctl/*.json` (`PermissionError` after the last case); set
`HOME` to a writable directory to keep the JSON.
