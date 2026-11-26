# llama-swap — one OpenAI-compatible endpoint in front of the local model
# stack. The `model` field of a request selects the backend: llama-swap starts
# it (or proxies to it) and shuts the previously running one down; an idle
# backend is unloaded after `globalTTL` (60 s) or the model's own `ttl`. Small
# models fit the 16 GB card whole; the 24 GB remote tiers are proxied.
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
  # Anything that fits the 16 GB card is served whole; the remote tiers run on
  # the 7900 XTX box and are proxied, never loaded here.
  modelDir = "/zero/ai/llama";
  llamaVulkan = lib.getExe' pkgs.llama-cpp-vulkan "llama-server";
  # Inkling-2-Mini is the only model here that needs a llama.cpp newer than
  # nixpkgs' 0.7.0: its `inkling2_loop` graph (#32694) and the looped-layer
  # scale fix (#32704, still open) live in packages/llama-cpp-inkling, kept as
  # a second binary so the rest of the stack stays on the stable build.
  llamaInkling = lib.getExe' pkgs.llama-cpp-inkling "llama-server";

  # Ornith-1.5-9B (MIT) — the same qwen35 family as the 27B, so the installed
  # llama.cpp already serves it. 5.4 GB of weights + 0.9 GB projector leave
  # room for a wide KV on the 16 GB card; 32k is the practical agent window.
  # Tool calls and vision ride the model's own chat template (--jinja).
  ornith9b = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/ornith-9b/Ornith-1.5-9B-Q4_K_M.gguf \
      --mmproj ${modelDir}/ornith-9b/mmproj-Ornith-1.5-9B-BF16.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 32768 -np 1 --flash-attn on --jinja
  '';

  # Inkling-2-Mini (Apache-2.0, 26.07B MoE, vision, 1M native window) — the
  # first tiers that run on `llamaInkling` rather than the stable build (see the
  # binding above). Two local variants, both with the f16 projector, measured
  # 2026-11-21 with 2.4 GiB of desktop on the card:
  #
  #   IQ3_XXS  10.87 GiB: prefill 232 t/s on a 7.5k prompt (287 at 2.9k),
  #            decode 27.4 t/s, 15.8-16.1 GiB of VRAM at 16k and at the 32k the
  #            tier ships — llama.cpp sizes the compute buffers from what is
  #            free, so the wider window costs prefill and nothing in memory.
  #   Q3_K_XL  12.68 GiB: 834 MiB left for KV and compute, so prefill drops to
  #            58.6 t/s and decode to 19.2 t/s. Better fidelity (KLD 0.0108 vs
  #            0.0269 on the publisher's table), and it needs a quiet desktop:
  #            the tier loads with 66 MiB to spare and a browser tab can push
  #            it into a spill.
  #
  # The price is speed, and it is the looped graph, not the card: layers 6-17
  # run three times, so the model costs ~3x the layer compute of a same-size
  # plain MoE. For scale, on the same 7.5k prompt and this box: qwen3.8-27b
  # prefills at 1051 t/s and decodes 37.9, the 9B ornith at 3671 / 88.5
  # (fleet probe, 2026-11-21). What it buys on the fleet's own tasks:
  # chem 13/13, fp 6.0/6, Lean 5/7 — the top two scores in the catalog.
  #
  # `inkling` is the IQ3 tier on purpose — the prefill is what any prompt over a
  # few hundred tokens feels, and it is 7x. An agent loop over a 20k prompt is
  # ~70 s here against ~5.5 min on Q3.
  #
  # `--reasoning-effort low` on both: the template's own knob. At the model's
  # 0.9 default a one-line RU question spent 500 tokens thinking and returned an
  # empty `content`; at `low` the same question answers in ~450 tokens, a third
  # of them thinking.
  inkling = ''
    ${llamaInkling} --device Vulkan0 \
      -m ${modelDir}/inkling-2-mini/Inkling-2-Mini-UD-IQ3_XXS.gguf \
      --mmproj ${modelDir}/inkling-2-mini/mmproj-F16.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 32768 -np 1 --flash-attn on --fit off --jinja \
      --reasoning-effort low
  '';

  inklingQ3 = ''
    ${llamaInkling} --device Vulkan0 \
      -m ${modelDir}/inkling-2-mini/Inkling-2-Mini-UD-Q3_K_XL.gguf \
      --mmproj ${modelDir}/inkling-2-mini/mmproj-F16.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 16384 -np 1 --flash-attn on --fit off --jinja \
      --reasoning-effort low
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

  # Qwen3.8-27B abliterated (IQ3_S, ~3.5 bpw) — the quality tier: dense 27B,
  # the highest bits-per-weight of anything served here. The image tier runs
  # the same weights with a projector in `qwen38vision` below. Dense
  # attention makes the KV cache expensive: q8_0 only leaves room for ~8k, so
  # both run q4_0 and the context is 32k — measured 2026-11-05 at 13.75 GiB
  # with the desktop (2.15 GiB of headroom), 1069 tok/s prefill on a 9.5k
  # prompt and 30.5 tok/s decode at that depth. The old "32k spills to ~4 tok/s"
  # note was wrong: it came from a llama-bench run taken while llama-swap still
  # held another model, so the two shared the card. Always `llmctl unload`
  # before measuring outside the router. 32k also fits the ~20k-token agent
  # prompt with room for its answer. `--reasoning off` is mandatory: without
  # it the reply arrives with an empty `content` (everything to reasoning).
  #
  # Vision (2026-11-11): the Qwen3.8 release is natively multimodal and the
  # huihui GGUF repo ships `mmproj-model-bf16.gguf` (0.87 GiB) for exactly
  # these weights; the file lives next to them as
  # `mmproj-qwen38-27b-bf16.gguf`. The text slot above stays projector-free on
  # purpose: `qwen38vision` below serves the same weights with the projector
  # and the `vision` alias, at half the context. Measured on 2026-11-11 with a
  # 963-token screenshot and a 2.9 GiB desktop: 32k peaked at 16020 of 16304
  # MiB (0.28 GiB left), 16k at 15660 (0.64 GiB left). The KV cache is small
  # here (the 27B is hybrid attention, most layers carry no per-token KV), so
  # halving the window buys only ~0.35 GiB — the image graph and the bf16
  # projector dominate. 16k still holds a dozen images, and the margin now
  # survives a browser tab.
  qwen38 = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/abliterated/Qwen3.8-27B-abliterated-IQ3_S.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 32768 -np 1 --flash-attn on --fit off --reasoning off \
      --cache-type-k q4_0 --cache-type-v q4_0 --jinja
  '';

  # The `vision` tier: same IQ3_S weights, plus the bf16 projector and a
  # smaller window (see the note above). Warm numbers on that screenshot:
  # 9.5 s, 753 tok/s prefill, 37.9 tok/s decode. The 8B that used to hold
  # `vision-fast` was faster (2.8 s, 93 tok/s) and transcribed the image with a
  # neutral prompt, but refused the structured "list the table rows verbatim"
  # request outright — the 27B answered it. Abliteration thins refusals, it does not
  # remove them, so the bigger model owns the alias.
  qwen38vision = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/abliterated/Qwen3.8-27B-abliterated-IQ3_S.gguf \
      --mmproj ${modelDir}/abliterated/mmproj-qwen38-27b-bf16.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 16384 -np 1 --flash-attn on --fit off --reasoning off \
      --cache-type-k q4_0 --cache-type-v q4_0 --jinja
  '';

  # Same tier, different quantizer: bartowski's IQ3_M of the orcarouter
  # uncensored Qwen3.8-27B (13.9 GB file, i.e. ~18% more bits than the IQ3_S
  # above), kept as the second half of the quant-source comparison. Flags are
  # identical to `qwen38` except the context: at 32k this file filled the card
  # to 15.8 of 15.9 GiB next to the desktop and the fim (:8012, removed
  # 2026-11-17) and reranker (:8013) servers, and the next start then died on allocation —
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
  # the fim (removed 2026-11-17) and the reranker (8397 MiB against 4025 MiB after
  # `/unload`) — 3.1 GiB of weights, ~1.07 GiB of q8_0 KV at 64k, the rest is
  # the compute buffer. 112 tok/s decode and 405 tok/s prefill on a cold short
  # prompt, ~2.5 s from request to first token. Quality is a 3B's: chem bench
  # 8/13 (the whole phosphorus problem 0/5), and it
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
  # 2000-token cap goes to thoughts, so no code arrives. So this is the local
  # tier that shows its work on easy-to-mid problems; hard ones belong to the
  # 27B quality tier or to Inkling.
  falconH1r = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/falcon/Falcon-H1R-7B-Q6_K.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 65536 -np 1 --flash-attn on --fit off --jinja \
      --cache-type-k q8_0 --cache-type-v q8_0 \
      --reasoning-format deepseek
  '';

  # Qwen3.8-4B (Apache-2.0) — the fast commit writer (opt-in). A
  # full-parameter distillation of the 180B Qwen3.8 teacher into the
  # Qwen3.5-4B architecture, so it carries the fleet's style at a 4B budget.
  # Measured 2026-11-11 with `llmctl bench commit` (nine real diffs, one-shot
  # example, one model resident): 76.9/90 against 82.6 for the 27B that writes
  # messages by default, at ~1.3 s per message, ~127 tok/s decode and 2.8 GB
  # of weights. What keeps it in the fleet is the card it does not take: it
  # loads next to a running Steam session rather than evicting it, so
  # `--model commit-4b` still commits while a game holds the GPU.
  # 16k, not the 32k the bench used: the prompt is bounded by
  # COMMIT_DIFF_CHARS (24000 characters, ~7k tokens), so 16k holds it plus the
  # reply with a 2x margin and keeps the tier cheap to swap in.
  # `--reasoning off` is not cosmetic: the distill thinks by default (its
  # teacher's chain of thought), and a client that cannot read
  # `reasoning_content` would wait through thoughts it never sees.
  qwen38small = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/commit/Qwen3.8-4B-Q4_K_M.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 16384 -np 1 --flash-attn on --fit off --reasoning off --jinja \
      --cache-type-k q8_0 --cache-type-v q8_0
  '';

  # gpt-oss-20b (MXFP4, 21B total / 3.6B active) — the only MXFP4 model that
  # fits the 16 GB card. Q4_K_M keeps the MoE experts in MXFP4 and quantizes
  # the rest; 10.8 GiB of weights plus q8_0 KV at 64k. The base OpenAI weights
  # need `--jinja` for the harmony template; low effort keeps a short chat from
  # burning the budget on reasoning. The model lost the FP planning bench in
  # the old abliterated build and returns as the fast MXFP4 tier, not as a
  # planner. Flags follow the removed 2026-11-05 slot (same file size, 12 GB).
  gptOss20b = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/mxfp4/gpt-oss-20b-Q4_K_M.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 65536 -np 1 --flash-attn on --fit off --jinja \
      --cache-type-k q8_0 --cache-type-v q8_0 -ub 1024 \
      --reasoning-effort low
  '';

  # Slot rows for `settings.models`. A local tier is just its command (plus an
  # optional ttl); a remote tier adds the ssh stop command and the proxy
  # endpoint, so the 21 entries stay one line each. `ttl = null` must emit no
  # key at all: a `ttl: null` in the YAML would be a different config.
  localSlot = name: cmd: ttl: aliases: {
    inherit name;
    value = {
      inherit cmd;
    }
    // lib.optionalAttrs (ttl != null) { inherit ttl; }
    // {
      aliases = lib.splitString " " aliases;
    };
  };
  remoteSlot = name: cmd: cmdStop: port: ttl: aliases: {
    inherit name;
    value = {
      inherit cmd cmdStop ttl;
      proxy = "http://192.168.0.144:${toString port}";
      checkEndpoint = "/health";
      aliases = lib.splitString " " aliases;
    };
  };

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

  # The remote tiers are one ssh line to the box; the start variants add the
  # keepalive, so the difference is the `opts` argument.
  # allow-absolute-home: the path is on the remote host, which has no root
  remoteCtl = opts: name: ''
    /run/current-system/sw/bin/ssh -T -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 ${opts}user@192.168.0.144 /home/user/bin/${name}
  '';
  remoteStart = remoteCtl "-o ServerAliveInterval=15 ";
  remoteStop = remoteCtl "";

  # Ornith-1.5-35B-A3B (MIT, 35B MoE with 3B active, 262k native): the coding
  # agent tier that replaced Gyro-Coder. Its weights live on the box's own
  # /srv/models (220 GB SSD), so a cold load is a local mmap instead of an SMB
  # stream; the 15 min TTL only releases the card between sessions.
  ornith = remoteStart "ornith-start";
  ornithStop = remoteStop "ornith-stop";

  # Qwen3.8-27B in MagicQuant MXFP4 (IQ4_XS, 13.95 GiB) with the stock 27B
  # bf16 projector, on the box's SSD: the MXFP4 quant of the local quality
  # tier, for a like-for-like comparison against IQ3_S on the 24 GB card.
  qwen27 = remoteStart "qwen27-start";
  qwen27Stop = remoteStop "qwen27-stop";

  # Inkling-2-Mini on the 24 GB card: Q4_K_XL (16.4 GiB) plus the f16 projector
  # and the DSpark drafter, on port 8097 (8090-8096 are the other tiers). The
  # GGUF in the repository *root* uses Unsloth's looped layout, and that is the
  # only layout this box can read: the stock `llama.cpp:server-rocm` image and
  # upstream mainline both refuse it (`unknown model architecture:
  # 'inkling2_loop'` is what the Mainline_Support files get, and mainline needs
  # the unmerged #32704 before they would answer correctly anyway). So this tier
  # runs Unsloth's own prebuilt ROCm build — b12588-mix-c0c3de8, gfx110X,
  # bundled ROCm libs — from a local `inkling-llama:local` image (debian:13-slim
  # plus the unpacked tarball in /opt/llama), and the DSpark drafter gives it
  # speculative decode. Box side: /home/user/bin/inkling-start|stop and the name
  # in llm-game-guard. Measured 2026-11-21:
  # 595-708 t/s prefill on a 7.5k prompt, 46-58 t/s decode with the drafter (the
  # spread is prompt length and cache warmth), ~4.6 min cold load streaming
  # 16.4 GiB over SMB — 2.6x the local IQ3 tier's prefill and 2.1x its decode
  # on the same probe, at Q4.
  #
  # BLOCKED until the weights move: they still sit under
  # /zero/ai/llama/gyro-coder/inkling-2-mini/ on trantor, and the SMB share that
  # carried them was removed with samba on 2026-11-25. Copy the 35 GB to
  # /srv/models on the box and point inkling-start there; until then this slot
  # cannot start.
  inklingRemote = remoteStart "inkling-start";
  inklingRemoteStop = remoteStop "inkling-stop";
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

      # One row per slot: this host's tiers run a local `cmd`, the remote ones
      # add the ssh stop command and the proxy endpoint (see the `localSlot` and
      # `remoteSlot` helpers above). The per-tier rationale sits above its row.
      models = builtins.listToAttrs [
        # Ornith-1.5-9B: fast agent/vision tier on the 16 GB card (MIT).
        (localSlot "ornith-1.5-9b" ornith9b 300 "ornith9b ornith-small vision-fast")
        # Inkling-2-Mini on the 16 GB card: see the `inkling` command for what
        # fits and what it costs. 15 min TTL because a cold load of 10.9 GiB
        # from /zero is ~20-30 s and the card is tight enough that the tier
        # should not sit on it once the conversation stops.
        (localSlot "inkling-2-mini" inkling 900 "inkling inkling-mini")
        # The quality variant: same model at Q3_K_XL, 61 t/s prefill. Kept for
        # the cases where the extra bits matter and the prompt is short; a
        # browser tab beside it can spill the model into RAM, so it is not the
        # default.
        (localSlot "inkling-2-mini-q3" inklingQ3 900 "inkling-q3 inkling-quality")
        (localSlot "oprover-8b" oprover 600 "oprover prover")
        (localSlot "qwen3.8-27b-abliterated" qwen38 null "qwen3.8 ru commit")
        # Same weights, projector + 16k window: the `vision` tier.
        (localSlot "qwen3.8-27b-vision" qwen38vision 30 "vision vision-27b")
        (localSlot "qwen3.8-27b-bartowski" qwen38bart null "bart27b bartowski")
        (localSlot "qwen3.8-27b-unsloth" qwen38unsloth null "unsloth27b ud")
        # The fast commit writer: one message costs a couple of seconds and the
        # 60 s global TTL already covers a second commit in the same session,
        # so the slot sets no TTL of its own — holding ~4 GiB longer would only
        # starve the chat tiers. The default writer is the 27B (`commit`
        # alias); this tier answers `--model commit-4b`.
        (localSlot "qwen3.8-4b" qwen38small null "commit-4b q4b")
        # Base OpenAI gpt-oss-20b, MXFP4 experts. Fast MoE tier for the 16 GB
        # card; it does not replace the 27B on quality.
        (localSlot "gpt-oss-20b" gptOss20b 600 "gpt-oss oss20b")
        (localSlot "falcon-h1-3b" falcon3b 600 "falcon-3b falcon3b falcon")
        (localSlot "falcon-h1r-7b" falconH1r 600 "falcon-h1r h1r reasoner")
        # Specialized small models: loaded on a request, unloaded after the
        # TTL. The editor's FIM backend is a separate service (modules/llm/fim.nix).
        (localSlot "k8s-qwen2.5-0.5b" k8s05 600 "k8s kubectl")
        (localSlot "magos-k8s-0.6b" magos 600 "magos k8s-diag")
        (localSlot "ocr" ocr 600 "paddleocr document")
        # The high-quality document tiers (see the cmds' comment for the
        # benchmark). Slow enough that the 10 min TTL matters: a page costs
        # ~30 s (olm) or ~13 s (dots), so repeated pages should stay warm.
        (localSlot "ocr-olm" ocrOlm 600 "olmocr doc-hq")
        (localSlot "ocr-dots" ocrDots 600 "dotsocr doc-fast")
        (localSlot "embed" embed 600 "embeddings")
        # Remote tiers on the 7900 XTX box: started and stopped over ssh,
        # requests go straight to them through `proxy`. 15 min TTL because a
        # cold load is minutes; `llmctl unload` still frees the card at once.
        # On the remote side a 1-minute watchdog stops the container if this
        # router disappears, so a crash or reboot here cannot strand 21 GiB of
        # VRAM on a machine nobody can reach.
        # Ornith-1.5-35B-A3B IQ4_XS: 18.8 GiB of weights + projector on the
        # box's own SSD, 32k by default. Replaces Gyro-Coder as the coding
        # agent tier; 3B active tokens make it much faster than the 27B dense
        # tiers on the same card. The freed 8090 port is reused.
        (remoteSlot "ornith-1.5-35b-a3b" ornith ornithStop 8090 900 "ornith ornith35b")
        # Qwen3.8-27B MagicQuant MXFP4 IQ4_XS + the 27B projector: the same
        # weights as the local quality tier, at MXFP4 on the 24 GB card.
        (remoteSlot "qwen3.8-27b-mxfp4" qwen27 qwen27Stop 8096 900 "qwen27-mxfp4 qwen3.8-mxfp4")
        # Inkling-2-Mini at Q4_K_XL on the 24 GB card — the same model as the
        # local tier one quant up, served by Unsloth's prebuilt ROCm build with
        # the DSpark drafter (see `inklingRemote` above for why that build).
        (remoteSlot "inkling-2-mini-q4" inklingRemote inklingRemoteStop 8097 900 "inkling-q4 inkling-24g")
      ];
    };
  };

  # nixpkgs ships a hardened DynamicUser unit; the spawned llama.cpp children
  # need the real user (render/video groups), /dev/kfd + /dev/dri and a
  # writable shader cache, and RADV/ACO JIT dies under MemoryDenyWriteExecute.
  # Keep nixpkgs' scheduling (auto-start; the daemon itself holds no VRAM),
  # but mirror the permissive shape the per-model units used to have.
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
