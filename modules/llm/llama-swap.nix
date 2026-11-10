# llama-swap — one OpenAI-compatible endpoint in front of the local model
# stack. The `model` field of a request selects the backend: llama-swap starts
# it (or proxies to it) and shuts the previously running one down; an idle
# backend is unloaded after `globalTTL` (60 s) or the model's own `ttl`. Small
# models fit the 16 GB card whole; the RAM tier (qwen3.8-flash) mmaps most
# weights from /zero. The 8B vision unit on
# :8080 is manual and separate.
# Clients use http://127.0.0.1:9292/v1.
#
# The per-model units stay available for manual use, but do not run them while
# llama-swap owns the GPU (16 GB VRAM, one big model at a time).
#
# Games get VRAM priority: a user-level guard unloads every llama-swap model
# while a game (Proton/Wine, Steam, gamescope) is running — see the
# llama-swap-game-guard unit below.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "llm";

  # Models live on the zero ZFS pool, never in the store (multi-GB files).
  # Anything that fits the 16 GB card is served whole; the RAM tiers keep only
  # a few layers on the card and mmap the rest from /zero. The 30B vision
  # weights (18 GB) were removed on 2026-11-06; the manual llama-server unit
  # serves the 8B model on :8080.
  modelDir = "/zero/ai/llama";
  llamaVulkan = lib.getExe' pkgs.llama-cpp-vulkan "llama-server";

  # Vision model (Vulkan/RADV): abliterated Qwen3-VL-8B — the base build
  # refuses too much for this stack. 64k of the 262k-native window: all 36
  # layers are full attention with 8 KV heads x 128 dims, so the KV is
  # ~78 KB/token at q8_0 — 64k costs ~4.8 GiB and leaves ~1.1 GiB of VRAM next
  # to the desktop, where 32k left 3.5 GiB sitting idle. Images eat thousands
  # of tokens, so the window is what the model is for. ~45 tok/s. Checked with
  # a real image plus ~50k tokens of text: 49,836 prompt tokens, 1763 tok/s
  # prefill, both shapes and colours read correctly. Text is fine too: the code
  # K7Q-42 was read correctly from a rendered image, with and without 31.6k
  # tokens of text in front of it (2229 tok/s prefill).
  vision8b = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/abliterated/Qwen3-VL-8B-abliterated-Q4_K_M.gguf \
      --mmproj ${modelDir}/abliterated/mmproj-qwen3-vl-8b-ablit-f16.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 65536 -np 1 --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0 --jinja
  '';

  # PaddleOCR-VL-1.6 (0.47B, Apache-2.0) — document parsing: layout, tables,
  # formulas, handwritten scans. A specialized doc-VLM; a general vision model
  # loses structure. llama-server learned the paddleocr arch (#18825), and the
  # GGUF carries its chat template. One page fits 16k with room to spare.
  ocr = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/ocr/PaddleOCR-VL-1.6-GGUF.gguf \
      --mmproj ${modelDir}/ocr/PaddleOCR-VL-1.6-GGUF-mmproj.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 16384 -np 1 --flash-attn on --jinja
  '';

  # The two document-OCR engines measured against the removed tesseract on a
  # 2026-11-08 scan (Russian prose, a table, a formula, noise + 0.4° rotation):
  # olmOCR-2 7B read 14/14 key fields at 0.00% CER in ~30 s per page; dots.ocr
  # 13/14 at 0.65% in ~13 s and emits tables as HTML. The 0.47B PaddleOCR-VL
  # above stays the 2 s path, so these two are for pages that have to be exact
  # and can wait. Both are Qwen2.5-VL-derived, 8k context is one page.
  ocrOlm = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/ocr-test/allenai_olmOCR-2-7B-1025-Q6_K.gguf \
      --mmproj ${modelDir}/ocr-test/mmproj-allenai_olmOCR-2-7B-1025-f16.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 8192 -np 1 --flash-attn on --jinja
  '';

  ocrDots = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/ocr-test/dots.ocr-Q8_0.gguf \
      --mmproj ${modelDir}/ocr-test/mmproj-dots.ocr-Q8_0.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 8192 -np 1 --flash-attn on --jinja
  '';

  # Qwen3-Embedding-0.6B (Apache-2.0) — retrieval embeddings. Qwen3 uses
  # last-token pooling, which the GGUF metadata does not set by itself.
  embed = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/embed/Qwen3-Embedding-0.6B-Q8_0.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 8192 -np 1 --embeddings --pooling last
  '';

  # Gemma 4 26B A4B — the MoE tier (25.2B total, 3.8B active), abliterated.
  # Q3_K_M on purpose: the IQ3_S build loops on multi-step prompts at greedy
  # decoding — a cold prefill falls into a repetition basin (the same prompt
  # with a warm prefix solves fine); repeat-penalty/DRY only mask it. Q3_K_M
  # does not loop: a chemistry olympiad and a math problem both finish,
  # ~105 tok/s at 32k. VRAM is tight (~16.2 GiB with the desktop open); if it
  # spills, drop -c to 16384. Text-only, the Qwen3-VL above handles images.
  # The base QAT/Q3 weights are gone: everything served here is uncensored.
  # `--fit off` is required: with auto-fit, the VRAM still held by the model
  # being swapped out makes llama.cpp silently offload a few layers, and a
  # partially offloaded gemma4 backend dies on the first request.
  gemma26b = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/abliterated/Gemma-4-26B-A4B-abliterated-Q3_K_M.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 32768 -np 1 --flash-attn on --fit off --reasoning off \
      --cache-type-k q8_0 --cache-type-v q8_0 --jinja
  '';

  # Qwen3.8-Flash-Next abliterated v2 (Swift IQ3_S, 78 GB in two shards, split
  # GGUF: point llama.cpp at -00001). 180B total but only 6B active: 48 layers
  # of ~0.95 GiB (the hot set, ~45 GiB; a token reads ~0.82 GiB of it — 10 of
  # 512 experts across 48 layers) plus a 26.8 GiB per-token embedding table
  # (320M rows, one row touched per token, so it stays cold). Four layers stay
  # on the card (~4.8 GiB buffer, 8.1 GiB with the desktop), the rest is mmap'd
  # from /zero. Measured 2026-11-05 with `llama-bench` (tg64, q8_0 KV, fa on):
  # decode 4.6 tok/s cold / 7.7 warm at -ub 512, 8.4-9.1 at -ub 1024; prefill
  # (pp1024) 80 tok/s at -ub 512, 133 at -ub 1024. `-ub 2048` is a trap (41
  # tok/s) and `-ngl` 8/10 buys nothing (7.6/7.4 warm): decode is bound by
  # reading expert weights from RAM, not by GPU compute. Speculative decoding
  # does not pay either — a Qwen3.5-4B draft (same 248320 vocab) costs 9%
  # because acceptance is low, `--spec-type ngram-simple` is noise, and
  # `draft-mtp` is rejected (no MTP head in this GGUF).
  #
  # Context is 128k of the 262k native window. The KV is cheap because only
  # the 12 full-attention layers keep keys (`full_attention_interval` 4, 2 KV
  # heads x 256 dims), so q8_0 costs ~4 GiB at 128k, ~8 GiB at 262k, and a
  # fully used 262k window would need a ~33 min prefill at 133 tok/s — not
  # usable. Depth does not slow decode down (tg32: 8.4 at d32768 vs 9.1 at
  # d8192), and 128k idles at 9.9 GiB VRAM with the desktop, ~6 GiB of
  # headroom (the game guard unloads the model before a game anyway).
  #
  # Thinking is ON: xhigh effort, 4096-token budget, thoughts moved to
  # `reasoning_content` by `--reasoning-format deepseek` (without it the reply
  # arrives with an empty `content`). What it buys is planning, not chemistry.
  # `llmctl bench fp`: 6.00/6 with thinking against 3.40/6 pinned off — every
  # case exact, ~24 min for the six (F3 alone 10 min), and the best score in
  # the fleet (the next best model is 4.4/6). Without thinking the same model
  # rebuilds spared dependents and misses the waves. The hard phosphorus task,
  # by contrast, is 5/5 either way (568 s off, 823 s on), so the earlier
  # "never finishes without thinking" note was an artefact of service restarts.
  # The 128k window was checked with a needle at 93,907 tokens: found, 87 tok/s
  # prefill (18 min), 5.9 tok/s decode at that depth. Planning survives depth
  # too: the F6 build-plan case buried in 22,855 tokens still scores 1.00
  # (10 min, 1.8k tokens), where the 120B drops to 0.70. The budget keeps a hard
  # prompt from running 20+ minutes at ~8 tok/s;
  # clients can opt out per request with
  # `chat_template_kwargs: {"enable_thinking": false}`.
  qwen38next = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/abliterated/qwen38-flash-next-iq3s/Swift-Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -ngl 4 -c 131072 -np 1 --flash-attn on --fit off --jinja \
      --cache-type-k q8_0 --cache-type-v q8_0 -ub 1024 \
      --reasoning-format deepseek --reasoning-effort xhigh \
      --reasoning-budget 4096
  '';

  # OProver-8B (Apache-2.0) — Qwen3-8B continued-pretrained and RL'd on Lean 4
  # (the OProofs corpus). It is trained for the agentic loop: retrieve verified
  # proofs, attempt, read the compiler error, repair — so it wants Lean
  # feedback in the prompt, not a one-shot chat. Q6_K (6.7 GB) fits the card
  # whole with ~2.5 GiB of q8_0 KV at 32k and scores within 1.5 points of the
  # 32B (MiniF2F Pass@32 91.8 vs 93.3). The 32B Q4_K_M is 19.8 GB: it does not
  # fit 16 GB and would decode from RAM, so the 8B is the local pick. Thinking
  # is off: the prover answers with a whole proof, and the lean bench caps the
  # reply at 2000 tokens.
  oprover = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/oprover/OProver-8B.Q6_K.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 32768 -np 1 --flash-attn on --fit off --jinja \
      --cache-type-k q8_0 --cache-type-v q8_0 --reasoning off
  '';

  # DeepSeek-Prover-V2-7B — the 2025 whole-proof baseline, kept for comparison
  # with the 2026 provers. Q8_0 (7.3 GB) fits the card whole, so there is no
  # reason to quantize it further. The GGUF carries the `<｜User｜>` template;
  # prompt it with a complete Lean statement, as the bench does.
  dsprover = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/deepseek-prover/DeepSeek-Prover-V2-7B-Q8_0.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 32768 -np 1 --flash-attn on --fit off --jinja \
      --cache-type-k q8_0 --cache-type-v q8_0
  '';

  # Qwen3.8-27B abliterated (IQ3_S, ~3.5 bpw) — the quality tier: dense 27B,
  # the highest bits-per-weight of anything served here, text-only. Dense
  # attention makes the KV cache expensive: q8_0 only leaves room for ~8k, so
  # both run q4_0 and the context is 32k — measured 2026-11-05 at 13.75 GiB
  # with the desktop (2.15 GiB of headroom), 1069 tok/s prefill on a 9.5k
  # prompt and 30.5 tok/s decode at that depth. The old "32k spills to ~4 tok/s"
  # note was wrong: it came from a llama-bench run taken while llama-swap still
  # held another model, so the two shared the card. Always `llmctl unload`
  # before measuring outside the router. 32k also fits the ~20k-token agent
  # prompt with room for its answer. `--reasoning off` is mandatory: without
  # it the reply arrives with an empty `content` (everything to reasoning).
  qwen38 = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/abliterated/Qwen3.8-27B-abliterated-IQ3_S.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 32768 -np 1 --flash-attn on --fit off --reasoning off \
      --cache-type-k q4_0 --cache-type-v q4_0 --jinja
  '';

  # Same tier, different quantizer: bartowski's IQ3_M of the orcarouter
  # uncensored Qwen3.8-27B (13.9 GB file, i.e. ~18% more bits than the IQ3_S
  # above), kept as the second half of the quant-source comparison. Flags are
  # identical to `qwen38` except the context: at 32k this file filled the card
  # to 15.8 of 15.9 GiB next to the desktop and the always-on fim (:8012) and
  # reranker (:8013) servers, and the next start then died on allocation —
  # llama-swap surfaced it as `proxy error: EOF` / 502 on every other request
  # (observed 2026-11-09). 16k keeps the start reliable and does not touch the
  # benchmark: the chem and fp prompts are a few hundred tokens.
  #   llmctl bench chem --models qwen3.8-27b-abliterated,qwen3.8-27b-bartowski
  # `llmctl unload` before any llama-bench run: two models on the 16 GB card
  # break the numbers (see the qwen38 comment above).
  qwen38bart = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/bartowski/orcarouter_Qwen3.8-27B-Uncensored-IQ3_M.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 16384 -np 1 --flash-attn on --fit off --reasoning off \
      --cache-type-k q4_0 --cache-type-v q4_0 --jinja
  '';

  # Third quant of the same tier: unsloth's UD-IQ3_S of the *base* (aligned)
  # Qwen3.8-27B, 12.0 GB. This is the size-matched control for `qwen38`: same
  # nominal quant, different quantizer, so a chem/fp delta against the
  # abliterated IQ3_S is a quantizer signal rather than a bitrate one. The
  # abliteration is still a confound (unsloth ships no uncensored 27B), which
  # is why the fleet does not serve it by default. 32k fits here, unlike the
  # bartowski slot above: measured 15.3 GiB with the desktop, i.e. the same
  # footprint as `qwen38` for a 1 GB larger file.
  qwen38unsloth = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/unsloth/Qwen3.8-27B-UD-IQ3_S.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 32768 -np 1 --flash-attn on --fit off --reasoning off \
      --cache-type-k q4_0 --cache-type-v q4_0 --jinja
  '';

  # ArduinoLLM-7B v2 (Q5_K_M, Apache-2.0) — the embedded tier: Qwen2.5-Coder-7B
  # plus a LoRA stage on Arduino/ESP32/Raspberry Pi/MicroPython/CircuitPython
  # and a continued-pretraining pass over ~500M tokens of real library sources
  # (Arduino core, micropython-lib, Adafruit CircuitPython Bundle). It answers in
  # the trained shape — wiring table, ASCII diagram, sketch, one design note —
  # and that format is why it beats a general coder here, not raw skill.
  #
  # Measured 2026-11-08 on the 9070 XT: 95 tok/s decode on a 584-token answer,
  # 1783 tok/s prefill (llama-bench: tg64 100.4, pp256 4198), ~5 s cold load,
  # 10.1 GiB of VRAM with the desktop open (5.4 GB of weights + ~1.1 GiB of
  # q8_0 KV at 32k). Unload llama-swap before measuring: the first probe read
  # 15 tok/s because the previous model was still being swapped out and the
  # weights had spilled to GTT.
  #
  # API discipline is the weak spot of a 7B this size: pin tables and sketch
  # structure come out right, library calls do not always — the probes produced
  # a non-existent `ESP32MQTT.h`, a non-existent `esp_deep_sleep_ms()`, and a
  # button sketch with a floating input and no INPUT_PULLUP. A bare "ESP32"
  # prompt also drifts to ESP-IDF (`gpio_pullup_enable(4)`) where the Arduino
  # line was wanted; say "Arduino IDE" when that is the target. Treat the output
  # as a reviewed draft, not as code to flash.
  #
  # Not abliterated, unlike the rest of the fleet: these are the only published
  # weights of this fine-tune, and wiring tasks are not where refusals live.
  embedded7b = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/embedded/ArduinoLLM-7B.Q5_K_M.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 32768 -np 1 --flash-attn on --fit off --jinja \
      --cache-type-k q8_0 --cache-type-v q8_0
  '';

  # Devstral Small 2 24B (Apache-2.0) — the agentic coding tier: Mistral's
  # SWE agent model (68.0% SWE-bench Verified, 55.7% multilingual), dense 24B
  # on the Mistral Small 3.1 geometry (40 layers, 8 KV heads x 128 dims) with
  # the Ministral 3 rope scaling (yarn over a 384k native window). Served at
  # 32k: the card is the limit, not the model. UD-IQ3_XXS (~3.5 bpw) because
  # Q4_K_M is 14.3 GB of weights and does not fit next to the desktop; KV is
  # q4_0 because q8_0 adds 2.8 GiB at 32k where q4_0 costs ~1.4 GiB.
  #
  # Measured 2026-11-08 with this exact command: 8 s to healthy with the file
  # in page cache, 13.1 GiB of VRAM next to a 2.8 GiB desktop (13.4 peak,
  # ~2 GiB of headroom), 1121 tok/s prefill and 48.7 tok/s decode on a short
  # prompt. `--jinja` is enough for the Mistral tool format: a request that
  # passes `tools` comes back as `tool_calls` with `arguments` as a JSON
  # string, so an agent harness needs no template hack.
  #
  # One-shot quality probe at this quant: it wrote a panic-free,
  # allocation-free `parse_version` that compiles, but accepted empty
  # components (`".."` -> `Some((0,0,0))`) and refused values above 1e9 that
  # still fit u32. Review the diffs it produces — this tier trades the last
  # bit of quality for fitting the card.
  #
  # Text-only on purpose: the release is vision-capable and the GGUF ships an
  # mmproj, but the projector is another ~0.9 GB and the `vision` tier owns
  # that job. Instruct model, so no reasoning flags apply.
  devstral = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/devstral/Devstral-Small-2-24B-Instruct-2512-UD-IQ3_XXS.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 32768 -np 1 --flash-attn on --fit off --jinja \
      --cache-type-k q4_0 --cache-type-v q4_0
  '';

  # Two Kubernetes specialists, both Q8_0 and new to the fleet: ~0.7 GiB of
  # weights together plus ~0.65 GiB of q8_0 KV. A 0.5B and a 0.6B beat the
  # general tiers here only at their own lane, and neither is abliterated —
  # these are the only published weights of the fine-tunes, and kubectl/YAML
  # is not where refusals live. Pick by job: `k8s-qwen2.5-0.5b` turns a
  # request into a kubectl line, `magos-k8s-0.6b` diagnoses a broken cluster
  # given the evidence.
  #
  # k8s_Qwen2.5-0.5B-Instruct (Apache-2.0) — Qwen2.5-0.5B-Instruct tuned on
  # chowmean/kubernetes_commands. In practice it is a `kubectl` command
  # generator in the trained shape ("Command: kubectl … / Description: …"):
  # straightforward verbs come out right (`kubectl scale deployment web
  # --replicas=5 -n shop`), the edges are the dataset's — "list pods not
  # Running" returns `--field-selector=status.phase!=Running -n *` instead of
  # `-A`, it bolts on `-n prod`, and a YAML-manifest request still comes back
  # as a command with an invented `--memory=`/`--max-size=` flag. The base
  # model is multilingual, so Russian prompts are answered in Russian, but
  # poorly (it defined a Deployment as "a namespace holding the state of all
  # containers"). Use it as a fast English kubectl-syntax helper — not as the
  # YAML tier and not for explanations.
  # Qwen3-Coder-30B-A3B-Instruct (Apache-2.0) — the agentic tier: 30B total but
  # 3B active, so one tool-calling turn costs a fraction of the dense 27B's and
  # a long chain does not take minutes. UD-Q2_K_XL (11.2 GB) is the quant that
  # fits next to the desktop and the always-on fim/reranker servers; the IQ3_XXS
  # build (12.2 GB) spilled ~1.5 GiB into GTT at 16k and was dropped.
  #
  # Measured 2026-11-10 on four chains of 3/5/6/12 tool calls (correct final
  # value, one call per turn): 3/3 in 3.9 s and the 12-step increments clean,
  # against 42.1 s for qwen3.8-27b and 2/3 for devstral. fp (build planning) is
  # the weak spot at 2.2/6, so route plans to qwen3.8-27b and steps here.
  #
  # Two protocol rules the model needs, both measured: call exactly one tool per
  # turn ("never guess what a tool can return"), and send tool results as plain
  # text with a `name` field rather than JSON-wrapped. Without them it batches
  # dependent calls, invents the values it should have read, and llama-server
  # answers 500 "Failed to parse tool call arguments as JSON".
  #
  # 16k, not 32k: 32k of KV does not fit next to the desktop, and 16k holds
  # roughly 12-15 chained calls before the harness has to summarise.
  qwen3Coder = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/qwen3-coder-30b/Qwen3-Coder-30B-A3B-Instruct-UD-Q2_K_XL.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 16384 -np 1 --flash-attn on --fit off --jinja \
      --cache-type-k q4_0 --cache-type-v q4_0
  '';

  # 32k is the native Qwen2.5 window (KV ~6 KB/token at q8_0, ~0.2 GiB);
  # measured 2026-11-08: +694 MiB of VRAM with the desktop open, 183-382 tok/s
  # decode, 2.0k tok/s prefill, cold start under 2 s.
  k8s05 = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/k8s/k8s-Qwen2.5-0.5B-Instruct.Q8_0.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 32768 -np 1 --flash-attn on --fit off --jinja \
      --cache-type-k q8_0 --cache-type-v q8_0
  '';

  # magos-k8s-0.6b (Apache-2.0) — Qwen3-0.6B with a full SFT stage (LoRA
  # merged) on ~24.5k kubehealth sessions, built as the local model behind
  # kubehealth: given collected evidence (events, describe, warnings on owned
  # objects, logs) it answers "what is wrong, the evidence, the fix, how sure"
  # in plain text, and calls four read-only tools when the cause sits in
  # another object (get_pod_logs, get_object_describe, get_object_events,
  # get_correlated_events). Thinking is ON: `--reasoning-format deepseek`
  # moves the thoughts to `reasoning_content`, and clients turn them off for
  # short notes with `chat_template_kwargs: {"enable_thinking": false}`. The
  # card asks for greedy or 0.2-0.3 sampling with repetition_penalty 1.0.
  # 8k, not the 40960 the GGUF declares: kubehealth compresses evidence to 8k
  # and the fine-tune was trained at 4096 seq len, so a longer window only
  # invites prompts outside its shape. Measured 2026-11-08: +1064 MiB of VRAM
  # (0.64 GB of weights + ~0.45 GiB of KV at 8k), 264-372 tok/s decode and
  # 10.3k tok/s prefill once the swap settles. Open-ended advice is its weak
  # spot: asked for the first checks on CrashLoopBackOff it drifts to
  # kubelet/kube-system nonsense; handed real evidence it names OOMKilled and
  # writes the fix. It needs a harness that feeds it the evidence and the tool
  # definitions — standalone, a 0.6B loses the thread.
  magos = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/k8s/magos-k8s-0.6b-q8_0.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 8192 -np 1 --flash-attn on --fit off --jinja \
      --cache-type-k q8_0 --cache-type-v q8_0 \
      --reasoning-format deepseek
  '';

  # Falcon-H1-3B-Instruct (TII, 3B, Falcon LLM license) — the small fast
  # general tier. Falcon-H1's hybrid is *parallel*, not alternating: every one
  # of the 32 blocks carries an attention branch (2 KV heads x 128 dims) next
  # to its Mamba-2 branch, so the KV cache is charged on all layers
  # (~16 KB/token at q8_0, i.e. ~1 GiB at 64k), on top of a fixed SSM state per
  # sequence. Q8_0 (3.35 GB) is nearly lossless and the whole model fits with
  # room to spare, so there is nothing to gain from a lower quant. 64k of the
  # 128k the GGUF declares: what limits a 3B here is quality, not the window.
  # The GGUF carries the ChatML template, hence `--jinja`.
  #
  # Measured 2026-11-10 on the 9070 XT: +4.3 GiB of VRAM next to the desktop,
  # the always-on fim and the reranker (8397 MiB against 4025 MiB after
  # `/unload`) — 3.1 GiB of weights, ~1.07 GiB of q8_0 KV at 64k, the rest is
  # the compute buffer. 112 tok/s decode and 405 tok/s prefill on a cold short
  # prompt, ~2.5 s from request to first token. Quality is a 3B's: chem bench
  # 8/13 (the whole phosphorus problem 0/5; the 8B vision tier 13/13), and it
  # slipped 17x23 -> 431 at temperature 0. Use it
  # as the fast chat/rewrite tier, not as a reasoner.
  falcon3b = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/falcon/Falcon-H1-3B-Instruct-Q8_0.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 65536 -np 1 --flash-attn on --fit off --jinja \
      --cache-type-k q8_0 --cache-type-v q8_0
  '';

  # Falcon-H1R-7B (TII, Oct 2025) — the local reasoner: Falcon-H1-7B-Base
  # cold-started on long reasoning traces and RL'd with GRPO, so it writes a
  # thought trace and then the answer. Same parallel hybrid as the 3B one size
  # up: 44 blocks, 2 KV heads x 128 dims, so the KV is ~22 KB/token at q8_0
  # (64k is ~1.4 GiB) and the GGUF declares 262k context (64k served: a 7B's
  # thoughts are long, not its working set). Q6_K (5.8 GiB) rather than Q8_0
  # (7.5 GiB): with the desk, fim and reranker on the card the difference is
  # 6 GiB of headroom against 4. The template carries `<think>`/`</think>`,
  # hence `--jinja`, and `--reasoning-format deepseek` moves the trace to
  # `reasoning_content` (without it the trace stays in `content`). Bench
  # numbers from the card are the vendor's; ours go in the catalog.
  #
  # Measured 2026-11-10 on the 9070 XT: +7.5 GiB of VRAM (11099 MiB resident
  # against 3634 MiB idle, next to the desktop, fim and reranker), 65 tok/s
  # decode, 471 tok/s prefill. Wall-clock is long because the traces are: a
  # carbonate olympiad problem is 2217 thought tokens, 49 s. The fleet's chem
  # bench is 8/13 — the same as the 3B — and the
  # phosphorus case never converges: it hit the 6000-token cap in 92 s, and a
  # 16000-token retry ran 4m18s and ended empty, still in `reasoning_content`.
  # Lean is 0/7 measured, kept as "-" in the catalog because the harness pins
  # thinking off for that bench and this template has no such switch: the
  # 2000-token cap goes to thoughts, so no code arrives (the same bench scores
  # 2/7 with thoughts on for qwen3.8-flash-next against 7/7 off). So this is
  # the local tier that shows its work on easy-to-mid problems; hard ones still
  # belong to the 180B on the other box.
  falconH1r = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/falcon/Falcon-H1R-7B-Q6_K.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 65536 -np 1 --flash-attn on --fit off --jinja \
      --cache-type-k q8_0 --cache-type-v q8_0 \
      --reasoning-format deepseek
  '';

  systemdUser = config.lib.neg.systemdUser;
  swapEnabled = enabled && config.services.llama-swap.enable;

  # Game guard: games get priority on the 16 GB of VRAM. While a game (native
  # via steamapps/, Proton/Wine, or anything under gamescope) is visible, every
  # model llama-swap has loaded is unloaded every 20 s, so a leftover vision
  # model cannot OOM the game; the next request re-spawns a backend on demand.
  gameGuard = pkgs.writeShellApplication {
    name = "llama-swap-game-guard";
    runtimeInputs = [
      pkgs.coreutils # sleep in the polling loop
      pkgs.curl # GET /unload against llama-swap
      pkgs.procps # pgrep for game process detection
    ];
    text = ''
      base="http://127.0.0.1:${toString config.services.llama-swap.port}"
      endpoint="$base/unload"
      gaming=0

      is_gaming() {
        # Match on the full command line (argv[0] may be a wrapper or a
        # renamed binary); patterns are anchored to a path separator or space.
        # Do NOT match pressure-vessel / srt-bwrap: the Steam client itself
        # keeps an srt-bwrap alive, so those matched permanently and unloaded
        # every model every 20 s while Steam was open. Proton games are still
        # caught below through their .exe process, native ones through their
        # steamapps/common/ path.
        if pgrep -f '(^|/)(gamescope|wine|wine64|wineserver|wine-preloader|wine64-preloader|lutris|heroic)( |$)' >/dev/null 2>&1; then
          return 0
        fi
        pgrep -f 'steamapps/common/|steam-launch-wrapper|\.exe' >/dev/null 2>&1
      }

      while true; do
        if is_gaming; then
          if [ "$gaming" = 0 ]; then
            echo "game detected — unloading GPU models"
            gaming=1
          fi
          # llama-swap keeps one model resident; drop whatever it holds so
          # the game gets the whole card.
          curl -fsS -o /dev/null --max-time 5 "$endpoint" || echo "unload request failed" >&2
          sleep 20
        else
          if [ "$gaming" = 1 ]; then
            echo "game stopped"
            gaming=0
          fi
          sleep 5
        fi
      done
    '';
  };

  # Gyro-Coder (Qwen3.8-Flash-Next, 125B MoE at 2.125 bpw) does not run on this
  # host: its 19.9 GiB of weights need the 24 GB card in the other machine
  # (192.168.0.144, RX 7900 XTX), which reads them read-only over SMB from
  # /zero/ai/llama/gyro-coder. llama-swap is only the router: `cmd` starts the
  # container there over ssh and stays attached so the log stream and the
  # process lifecycle stay visible, `proxy` sends the requests straight to it,
  # `cmdStop` stops the container on unload. Nothing here touches trantor's own
  # 16 GB card, so this tier never competes with the local models.
  #
  # Two reasons the model entry below differs from the local ones: the remote
  # server has a fixed port instead of ${PORT} (hence `proxy`), and a cold load
  # is ~3.5 min -- weights arrive over the LAN and the shaders warm up -- so its
  # TTL is 15 min rather than the 60 s global one.
  # llama-swap execs `cmd` directly -- no shell -- so this has to be a plain
  # argv: absolute ssh path, simple flags, one-word remote command. The real
  # container invocation lives in /usr/local/bin/gyro-coder-start on the other
  # machine (a shell-style cmd with quotes and `|| true` fails with
  # `exec: "ssh": executable file not found in $PATH`).
  # accept-new: unknown hosts are trusted once, a *changed* host key still fails.
  gyroCoder = ''
    /run/current-system/sw/bin/ssh -T -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o ServerAliveInterval=15 user@192.168.0.144 gyro-coder-start
  '';

  gyroCoderStop = ''
    /run/current-system/sw/bin/ssh -T -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 user@192.168.0.144 gyro-coder-stop
  '';

  # OrcaCyber Nano 1.0 (27B vision-language) on the same 7900 XTX box, but on
  # stock upstream llama.cpp with the ROCm backend: the Agention Vulkan fork the
  # gyro tier runs is ~4x slower for arch `qwen35` (8.6 vs 36.4 tok/s decode,
  # measured 2026-11-08). The start/stop scripts live in the remote user's home
  # rather than /usr/local/bin because no root is available there; the `cmd`
  # still has to be a plain argv, so the remote command is one absolute path.
  # allow-absolute-home: the path is on the remote host, which has no root
  nano = ''
    /run/current-system/sw/bin/ssh -T -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o ServerAliveInterval=15 user@192.168.0.144 /home/user/bin/nano-start
  '';

  # allow-absolute-home: the path is on the remote host, which has no root
  nanoStop = ''
    /run/current-system/sw/bin/ssh -T -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 user@192.168.0.144 /home/user/bin/nano-stop
  '';
in
{
  services.llama-swap = lib.mkIf enabled {
    enable = lib.mkDefault true;
    listenAddress = "127.0.0.1";
    port = 9292;

    settings = {
      healthCheckTimeout = 600;
      # Idle backends unload after a minute: the card is shared with the
      # desktop (~4 GB with Steam and Vivaldi) and with games, so nothing may
      # sit on it unused. A cold load costs 8-20 s, so a minute is still long
      # enough not to reload between messages.
      globalTTL = 60;
      models = {
        "qwen3-vl-8b-abliterated" = {
          cmd = vision8b;
          aliases = [
            "vision"
            "vision-8b"
            "qwen3-vl-8b"
          ];
        };
        "gemma4-26b-abliterated" = {
          cmd = gemma26b;
          aliases = [
            "gemma4"
            "gemma4-26b"
          ];
        };

        "qwen3.8-flash-next-abliterated" = {
          cmd = qwen38next;
          ttl = 900;
          aliases = [
            "qwen3.8-flash"
            "next"
          ];
        };
        "oprover-8b" = {
          cmd = oprover;
          ttl = 600;
          aliases = [
            "oprover"
            "prover"
          ];
        };
        "deepseek-prover-v2-7b" = {
          cmd = dsprover;
          ttl = 600;
          aliases = [
            "deepseek-prover"
            "dsprover"
          ];
        };
        "qwen3.8-27b-abliterated" = {
          cmd = qwen38;
          aliases = [
            "qwen3.8"
            "ru"
          ];
        };
        "qwen3.8-27b-bartowski" = {
          cmd = qwen38bart;
          aliases = [
            "bart27b"
            "bartowski"
          ];
        };
        "qwen3.8-27b-unsloth" = {
          cmd = qwen38unsloth;
          aliases = [
            "unsloth27b"
            "ud"
          ];
        };
        "arduinollm-7b" = {
          cmd = embedded7b;
          # Specialist, not a daily driver: a longer TTL only wastes the card.
          ttl = 600;
          aliases = [
            "embedded"
            "arduino"
          ];
        };

        "devstral-small-2-24b" = {
          cmd = devstral;
          # A daily coding driver, not a one-off probe: keep it resident for
          # ten minutes so the 60 s global TTL does not reload it between
          # messages (a cold load is ~8 s of 9.4 GB from /zero).
          ttl = 600;
          aliases = [
            "devstral"
            "coder"
          ];
        };

        "qwen3-coder-30b" = {
          cmd = qwen3Coder;
          # Same reasoning as devstral: agent work arrives in chains of calls,
          # and a reload between them would add ~10 s of 11 GB from /zero.
          ttl = 600;
          aliases = [
            "qwen3-coder"
            "agent"
          ];
        };

        "falcon-h1-3b" = {
          cmd = falcon3b;
          # A general fast tier, not a specialist: ten minutes like the other
          # daily drivers, so a chat turn does not pay for a reload.
          ttl = 600;
          aliases = [
            "falcon-3b"
            "falcon3b"
            "falcon"
          ];
        };

        "falcon-h1r-7b" = {
          cmd = falconH1r;
          # A reasoner is not a warm path: a cold load costs a few seconds and
          # an answer a minute of thinking, so keep it for ten minutes like
          # the other daily tiers.
          ttl = 600;
          aliases = [
            "falcon-h1r"
            "h1r"
            "reasoner"
          ];
        };

        # Specialized small models: loaded on a request, unloaded after the
        # TTL. The editor's FIM backend is a separate service (modules/llm/fim.nix).
        "k8s-qwen2.5-0.5b" = {
          cmd = k8s05;
          # Specialist, not a daily driver: a longer TTL only wastes the card.
          ttl = 600;
          aliases = [
            "k8s"
            "kubectl"
          ];
        };
        "magos-k8s-0.6b" = {
          cmd = magos;
          ttl = 600;
          aliases = [
            "magos"
            "k8s-diag"
          ];
        };
        "ocr" = {
          cmd = ocr;
          ttl = 600;
          aliases = [
            "paddleocr"
            "document"
          ];
        };
        # The high-quality document tiers (see the cmds' comment for the
        # benchmark). Slow enough that the 10 min TTL matters: a page costs
        # ~30 s (olm) or ~13 s (dots), so repeated pages should stay warm.
        "ocr-olm" = {
          cmd = ocrOlm;
          ttl = 600;
          aliases = [
            "olmocr"
            "doc-hq"
          ];
        };
        "ocr-dots" = {
          cmd = ocrDots;
          ttl = 600;
          aliases = [
            "dotsocr"
            "doc-fast"
          ];
        };
        "embed" = {
          cmd = embed;
          ttl = 600;
          aliases = [ "embeddings" ];
        };

        # The only remote tier: started and stopped over ssh on the 7900 XTX
        # box, requests go straight to it through `proxy`. 15 min TTL because a
        # cold load costs ~3.5 min; `llmctl unload` still frees the card at once.
        # On the remote side a 1-minute watchdog stops the container if this
        # router disappears, so a crash or reboot here cannot strand 21 GiB of
        # VRAM on a machine nobody can reach.
        "gyro-coder" = {
          cmd = gyroCoder;
          cmdStop = gyroCoderStop;
          proxy = "http://192.168.0.144:8090";
          checkEndpoint = "/health";
          ttl = 900;
          aliases = [
            "gyro"
            "gyrocoder"
          ];
        };

        # Same box, second remote tier. 15.7G build + DFlash2 drafter + mmproj
        # occupy 22.2 GiB of the 24 GiB card at 32k and decode at ~42 tok/s; a
        # cold load is ~30 s (page cache warm from the earlier runs), so the
        # 15 min TTL only exists to release the card between sessions.
        "nano" = {
          cmd = nano;
          cmdStop = nanoStop;
          proxy = "http://192.168.0.144:8094";
          checkEndpoint = "/health";
          ttl = 900;
          aliases = [
            "orcacyber"
            "cyber"
          ];
        };
      };

    };
  };

  # nixpkgs ships a hardened DynamicUser unit; the spawned llama.cpp children
  # need the real user (render/video groups), /dev/kfd + /dev/dri and a
  # writable shader cache, and RADV/ACO JIT dies under MemoryDenyWriteExecute.
  # Keep nixpkgs' scheduling (auto-start; the daemon itself holds no VRAM),
  # but mirror the permissive shape of the lib/llama-server.nix units.
  systemd.services.llama-swap = lib.mkIf enabled {
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = config.users.main.name;
      PrivateUsers = lib.mkForce false;
      ProtectHome = lib.mkForce false;
      ProtectSystem = lib.mkForce false;
      MemoryDenyWriteExecute = lib.mkForce false;
      SystemCallFilter = lib.mkForce [ ];
    };
  };

  # User-level guard (no root needed to call /unload): unloads llama-swap
  # models while a game runs; see the gameGuard script above.
  systemd.user.services.llama-swap-game-guard = lib.mkIf swapEnabled (
    systemdUser.mkUserService {
      presets = [
        "defaultWanted"
        "restartOnFailure"
      ];
      description = "Unload llama-swap models while a game is running";
      after = [ "network.target" ];
      serviceConfig = {
        Type = "simple";
        RestartSec = 5;
        ExecStart = lib.getExe gameGuard;
      };
    }
  );
}
