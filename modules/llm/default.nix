#
# Local LLM stack
# (moved out of the docs tree; keep it in sync with the code it describes)
#
#
# How the local neural-network stack on the `trantor` host works, what is enabled, and how to operate
# it.
#
# Everything below is gated on a single feature flag:
#
#     features.llm.enable = true;
#
# defined in `modules/features/misc.nix` (default `false`) and enabled for `trantor` in
# `hosts/trantor/default.nix`.
#
# ## Components
#
# ### Ollama (LLM serving, ROCm-accelerated)
#
# - Module: `modules/llm/{default,ollama}.nix`
# - Package: `pkgs.ollama-rocm` (ROCm build)
# - Bind: `0.0.0.0:11434` (firewall opened)
# - Model store: `/zero/ai/ollama` — lives on the `zero` ZFS pool, never on system disks. An existing
#   413 GB store (18 models: qwen3 32b/235b, llama3.3 70b, qwen3-coder, devstral, qwq, abliterated
#   variants, …) is already in place; no re-download needed.
# - Service user: `ollama` (static user, `DynamicUser = false` so ownership of the store stays
#   stable). `neg` is in the `ollama` group and can manage model files.
# - tmpfiles ensure `/zero/ai/ollama` is `0770 ollama:ollama` (with `Z` recursive fixup at boot).
# - GPU: RX 9070 XT (Navi 48, gfx1201). The pinned nixpkgs' ROCm ships gfx1201 code objects, so no
#   `HSA_OVERRIDE_GFX_VERSION` is needed.
#
# CLI:
#
#     ollama list
#     ollama pull qwen3:32b
#     ollama run qwen3:32b
#
# - colibrì (GLM-5.2 CPU engine) removed 2026-11-02; its weights were deleted
#   2026-11-05 (358 GB back on `zero`). The empty `/zero/ai/glm52_i4` directory
#   stays: `/zero/ai` is root-owned, so unlinking it needs root.
#
# ### llama-server (qwen3-vl vision, Vulkan/RADV)
#
# - Module: `modules/llm/llama-server.nix`
# - Engine: `pkgs.llama-cpp-vulkan`, GPU-backed (RX 9070 XT, RADV).
# - Role: local vision engine for the `vision-review` skill — images never leave the machine.
# - Model dir: `/zero/ai/llama` (qwen3-vl-8b GGUF + mmproj) — on the `zero` ZFS pool, never on
#   system disks.
# - Deliberately not auto-started; start on demand:
#       systemctl start llama-server          # 8b on 127.0.0.1:8080
#       /zero/ai/llama/start-llama-server.sh  # same, manual run (optional port/model args)
#
# ### llama-swap (one OpenAI-compatible endpoint, 127.0.0.1:9292)
#
# - Module: `modules/llm/llama-swap.nix`; the `model` field selects a backend,
#   one model is resident at a time (16 GB VRAM, ~4 GB of it is the desktop).
# - Every model the router serves is uncensored: abliterated Gemma 4 26B
#   (Q3_K_M), Qwen3-VL-8B and the Qwen tiers. The base Gemma/Qwen
#   weights and
#   the censored ollama peers were removed — aligned models refuse too much for
#   this stack. Base files still lie on disk until they are deleted.
# - Idle backends are unloaded after `globalTTL` 60 s, and the game guard
#   unloads them at once when a game starts.
# - One model is resident at a time. All of them fit the 16 GB card except the
#   streaming tier (Qwen3.8-Flash-Next); the 8B vision unit on :8080 is
#   separate and started by hand.
# - Vulkan (`pkgs.llama-cpp-vulkan`) is the fast path on gfx1201; `--cpu-moe`
#   is a trap here (3-8 tok/s).
# - Models (quant, measured on 2026-11-05):
#
#   | model        | weights                                  | ctx | VRAM  | tok/s |
#   | ------------ | ---------------------------------------- | --- | ----- | ----- |
#   | gemma4-26b   | Gemma-4-26B-A4B-abliterated Q3_K_M (MoE)  | 32k | 16.2G | 105-110 |
#   | qwen3-vl-8b  | Qwen3-VL-8B-abliterated Q4 + mmproj      | 64k | 14.8G | 45    |
#   | qwen3.8-27b  | Qwen3.8-27B-abliterated IQ3_S (dense)    | 32k | 13.8G | 30-36 |
#   | vision-27b   | same IQ3_S + bf16 mmproj                 | 16k | 15.3G | 37.9  |
#   | qwen3.8-next | Qwen3.8-Flash-Next abl-v2 IQ3_S          | 128k| 6.0G  | 5.9   |
#
# - `qwen3.8-27b-abliterated` (`ru` alias) is the quality tier: dense 27B at
#   ~3.5 bpw, the highest bits-per-weight served here. Dense KV is expensive,
#   so both caches run q4_0 and the context is 32k (13.75 GiB with the desktop,
#   30.5 tok/s at a 9.5k prompt). The old "32k spills" claim came from a
#   measurement taken while another model was resident. `--reasoning off` is
#   mandatory — without it the reply carries an empty `content`.
#   Since 2026-11-11 the same weights also serve images through a second slot,
#   `qwen3.8-27b-vision` (aliases `vision`, `vision-27b`): it adds the
#   `mmproj-qwen38-27b-bf16.gguf` projector (0.87 GiB, published by huihui for
#   exactly these weights) and halves the context to 16k. The split is forced
#   by VRAM: with the projector at 32k the backend peaked at 16020 of 16304
#   MiB next to a 2.9 GiB desktop (0.28 GiB of headroom), at 16k 15660 (0.64
#   GiB). The 27B is hybrid attention, so the KV is small and the window is
#   not what costs — the image graph and the projector are. Measured warm on
#   a 963-token screenshot: 9.5 s, 753 tok/s prefill, 37.9 tok/s decode.
#   The 8B Qwen3-VL stays as `vision-fast` (2.8 s, 93 tok/s, 64k) and reads
#   the same image with a neutral prompt, but refused the structured
#   "list the table rows verbatim" request — that is why the alias moved.
#   Why the 27B: it is the only bigger vision model that fits next to the
#   desktop — the removed 30B-A3B needs 11.04 GB at IQ3_XXS plus a 1.01 GB
#   projector and ~1.6 GiB of KV, i.e. ~17.3 GiB.
# - Quant-source comparison (2026-11-09): the same tier built by three
#   quantizers, measured with the same harness (chem 6 tasks/13 values, fp 6
#   cases, two repetitions each, temperature 0, prompt cache off, one model
#   resident at a time, no game running):
#
#   | weights                                     | file  | ctx | VRAM | chem  | fp   | tok/s |
#   | ------------------------------------------- | ----- | --- | ---- | ----- | ---- | ----- |
#   | Qwen3.8-27B-abliterated IQ3_S (current)     | 10.9G | 32k | 14.0 | 12/13 | 3.70 | 39.4  |
#   | orcarouter-27B-Uncensored IQ3_M (bartowski) | 12.9G | 16k | 15.5 | 13/13 | 3.30 | 35.1  |
#   | Qwen3.8-27B UD-IQ3_S (unsloth, aligned)     | 11.2G | 32k | 14.0 | 13/13 | 4.20 | 38.8  |
#
#   Both repetitions scored identically, so the deltas are reproducible rather
#   than sampling noise; `tok/s` is a warm 294-token answer after the load.
#   The chem gap is a single graded value on P6 (phosphorus): the current
#   quant drops the 3.87 factor that both others keep. fp runs the other way —
#   the aligned unsloth build leads by 0.5, i.e. abliteration costs planning
#   quality. bartowski's IQ3_M is the weakest trade: 1.5 GiB more VRAM than
#   unsloth at half the context (at 32k it filled 15.8 of 15.9 GiB and the
#   backend then died on allocation, surfacing as `proxy error: EOF`/502), no
#   chem gain over the same-size unsloth build and 0.4 less fp. Only
#   bartowski's build is uncensored (the orcarouter finetune); unsloth ships no
#   abliterated 27B, so the fleet keeps the current IQ3_S — the two alternatives
#   stay as slots (`bart27b`, `ud`) for re-measuring, not as defaults.
# - The game guard matches any argv carrying a `.exe` token, so a command that
#   names a game file (`pgrep -f RCTClassic.exe`) keeps the guard latched in
#   "game detected" by itself: it then unloads the backend every 20 s and every
#   local-model request dies with 502. Use a bracketed pattern
#   (`pgrep -f 'RCT[C]lassic'`) — or any spelling without the literal token —
#   when benching or driving models while Steam is open.
#   The detection itself lives in `modules/llm/llama-swap.nix`.
# - `gemma4-26b` is text-only (the projector does not fit next to 12.5 GB of
#   weights); `qwen3.8-27b` serves images as the `vision` alias and
#   `qwen3-vl-8b` is the `vision-fast` path.
# - `qwen3.8-flash-next-abliterated` (`qwen3.8-flash`, `next` aliases) is the
#   next tier: 78 GB split GGUF (Swift IQ3_S of the huihui v2 abliteration;
#   pass the -00001 shard), 180B total but 6B active, 262k-native. Four layers
#   on the card (~4.8 GiB buffer, 8.1 GiB total with the desktop), the rest
#   mmap'd from `/zero`. Measured 2026-11-05: 5.9 tok/s decode on a cold page
#   cache. `--reasoning off` is mandatory — it thinks by default and returns an
#   empty `content`. The repo also ships an mmproj, so vision can be added
#   without another model. It is also the core-Lean tier: 7/7 on
#   `llmctl bench lean` (2026-11-05), the only streaming model that solved all
#   seven tasks, so route Lean work here.
# - Context is cheap where only part of the layers keep keys: moving 32k -> 64k
#   cost <200 MB with q8_0 KV, and `-ub 1024` bought +29% prefill.
#   MTP speculation was tested and rejected: slower (46 vs 65 tok/s) and it
#   answers wrong on quantized targets (llama.cpp issue #25618).
# - The Gemma command starts with `--fit off`: auto-fit reads the
#   VRAM of the model being swapped out as free, offloads a few layers, and
#   gemma4 then crashes on the first request.
# - The ollama store still holds base models for `rag-search`; the router does
#   not expose them.
#
# ### voxinput (voice → text)
#
# - Module: `modules/llm/pkgs.nix`
# - Installed when `features.llm.enable` — voice-to-text via LocalAI/OpenAI-compatible endpoint +
#   `dotool`/`uinput`.
#
# ### pic-ocr (screenshot → text, engine choice)
#
# - Script: `packages/local-bin-desktop` (pic-ocr) (installed to `~/.local/bin`).
# - Single engine: local **neural** OCR via Ollama's `qwen3-vl-abliterated:8b` (override with
#   `PIC_OCR_NN_MODEL`). Images never leave the machine. Tesseract was removed on 2026-11-08: on the
#   scan benchmark it lost 7 of 14 key fields and produced garbage on formulas, while this model
#   read 14/14 (see modules/cli/ocr.nix for the numbers).
# - Usage: `pic-ocr [--engine=nn] IMAGE`; with no IMAGE it captures a region (`slurp`).
#   Result goes to the clipboard + `notify-send`. `-m/--menu` is kept as an alias for nn.
# - Wired into the quickshell **ScreenshotToast**: after a Hyprland screenshot (`M4+SHIFT+R`,
#   `M4+SHIFT+CTRL+R`) the toast offers **OCR** and **OCR NN**; both now run the neural engine
#   (the buttons and events were kept to avoid a scene change in this patch).
#
# ### local-ai user service (fallback)
#
# - `modules/user/nix-maid/sys/user-services.nix` — user-level Ollama fallback for hosts **without**
#   the system `services.ollama` (it would conflict on port 11434). On `trantor` the system service is
#   enabled, so the user service stays off. Models also on `/zero/ai/ollama` / `/zero/ai/localai`.
#
# ### stable-diffusion.cpp (text-to-image, Vulkan)
#
# - Package: `pkgs.stable-diffusion-cpp` overridden with `vulkanSupport = true` (RADV on the RX 9070
#   XT). In this nixpkgs rev the binaries are `sd-cli`/`sd-server` (not `sd` — no conflict with the
#   Rust `sd` sed replacement).
# - Role: fast local T2I without touching ComfyUI/ROCm — pure Vulkan, fits the "Vulkan-first"
#   preference.
# - Model dir: `/zero/ai/image` — SDXL base checkpoint + VAE, TAESD decoder, FLUX.1-schnell (GGUF
#   q4_k) + clip_l/t5xxl/ae.
# - Binary: `sd-cli`. **Verified working recipe (RX 9070 XT, Vulkan)** — SDXL 1024×1024, 20 steps, ~23
#   s/image:
#
#     # SDXL — use --taesd! Full VAE decode needs a single >4 GB Vulkan buffer (RADV caps
#     # maxMemoryAllocationSize at ~4 GiB → OOM), and CPU VAE decode is 170 s and yields blank output.
#     # TAESD decodes in <1 s with real content. UNet runs on Vulkan (~1.2 it/s).
#     sd-cli -m /zero/ai/image/sd_xl_base_1.0.safetensors \
#        --vae /zero/ai/image/sdxl_vae.safetensors \
#        --taesd /zero/ai/image/taesdxl.safetensors \
#        -H 1024 -W 1024 -p "a red apple on a wooden table" \
#        --steps 20 --cfg-scale 6 --sampling-method euler \
#        --backend diffusion=vulkan0,clip=cpu -v
#
#     # FLUX.1-schnell (GGUF unet + separate encoders; cfg-scale 1, 4 steps).
#     # t5xxl MUST be on CPU (fp8 4.9 GB + unet 6.4 GB overflows VRAM; the process dies
#     # silently otherwise). FLUX VAE decode fits Vulkan (2 GB buffer) — no TAESD needed.
#     # Verified: ~39 s end-to-end (mostly CPU t5xxl prompt encoding; sampling 2.5 s).
#     sd-cli --diffusion-model /zero/ai/image/flux1-schnell-q4_k.gguf \
#        --vae /zero/ai/image/ae.safetensors \
#        --clip_l /zero/ai/image/clip_l.safetensors \
#        --t5xxl /zero/ai/image/t5xxl_fp8_e4m3fn.safetensors \
#        -p "a cute cat sitting on a windowsill, golden hour light" \
#        --cfg-scale 1.0 --sampling-method euler --steps 4 -v \
#        --backend "diffusion=vulkan0,clip=cpu,t5xxl=cpu"
#
# - GPU notes (verified on this host): q4_k GGUF ≈ 6.4 GB in VRAM; q8_0 ≈ 12 GB — only with a lighter
#   t5. FLUX needs `--cfg-scale 1.0`; SDXL default cfg ~6. RADV caps a single Vulkan allocation at ~4
#   GiB (`maxMemoryAllocationSize = 0xfffffffc`) — any component needing a bigger compute buffer (full
#   VAE decode = 8.5 GB) must go to CPU or use TAESD.
#
# ### Embeddings & reranker (RAG)
#
# - Embeddings: **qwen3-embedding** (already in the ollama store, Q4_K_M, 4096 dims) — use via
#   `ollama pull qwen3-embedding` + `POST /api/embed` or OpenAI-compatible `/v1/embeddings`.
# - llama-swap also serves `Qwen3-Embedding-0.6B` (Apache-2.0, Q8_0 GGUF on /zero, last-token
#   pooling, 1024 dims) as the `embed`/`embeddings` slot: `POST /v1/embeddings` to port 9292.
#   It loads on demand and is unloaded by the TTL; the Ollama tag stays for rag-search, whose
#   index is 4096-dim and would need a reindex to switch.
# - Reranker: `bge-reranker-v2-m3-Q4_K_M.gguf` in `/zero/ai/embeddings`, served by the
#   `llama-rerank` system service (`modules/llm/rerank.nix`) on port 8013 with rank pooling,
#   always on. It is deliberately NOT a llama-swap slot: llama-swap proxies the chat/embeddings
#   endpoints but not `/v1/rerank` (the request hangs), and Qwen3-Reranker is a causal LM that
#   needs yes/no chat-template scoring — `--pooling rank` on its GGUF produced near-zero,
#   reversed scores, so bge is the llama.cpp-compatible choice. `rag-search` points at 8013 by
#   default and still spawns its own instance when the service is down.
# - Both are multilingual (RU/EN); reranker should be the top-k filter before LLM context assembly.
#
# ### FIM completion (editor)
#
# - Service: `services.llama-fim` (`modules/llm/fim.nix`) — llama.cpp with Qwen2.5-Coder-1.5B
#   Q8_0 (`/zero/ai/llama/fim`), port 8012, Vulkan device, 4k ctx. A **user** unit without
#   `wantedBy`: Neovim starts it on VimEnter and stops it when the last nvim exits, so the
#   1.5B model does not compete with the chat tiers for the card.
# - Client: `minuet-ai.nvim` (`files/nvim/lua/plugins/completion/minuet.lua`) with the Qwen FIM
#   tokens over `/v1/completions`; ghost text on `<M-CR>`, line on `<M-l>`, next/prev `<M-]>`/
#   `<M-[>`, dismiss `<M-e>`. `<C-j>`/`<C-k>` stay with LuaSnip.
# - `-c 4096` is enough: minuet sends 2048 characters of context (~500 tokens).
#
# ### OCR (documents)
#
# - `PaddleOCR-VL-1.6` (0.47B, Apache-2.0, GGUF + mmproj on /zero) is a llama-swap model:
#   request `model: "ocr"` (aliases `paddleocr`, `document`) on port 9292 with an OpenAI image
#   message and the prompt `OCR:` (also `Table Recognition:`, `Formula Recognition:`, `Chart
#   Recognition:`, `Seal Recognition:`). llama.cpp merged the paddleocr arch (#18825); one page
#   fits the 16k context. Verified on a rendered invoice: exact Russian text and totals.
# - `ocr FILE...` (`modules/cli/ocr.nix`) is the CLI over that slot: images directly, PDFs page
#   by page via pdftoppm; `--table/--formula/--chart/--seal` switch the prompt, `-o out.md`
#   writes a file.
#
# ### Speech recognition (sherpa-onnx, CPU)
#
# - `gigaam-asr FILE.wav` — GigaAM-v3 (MIT, ru/en; RNNT, int8 encoder) on `/zero/ai/asr/gigaam-v3`.
# - `parakeet-asr FILE.wav` — Parakeet-TDT-0.6B-v3 (CC-BY-4.0, 25 European languages incl. ru/uk)
#   on `/zero/ai/asr/parakeet-v3`.
# - Both run through sherpa-onnx on the CPU (no VRAM, no torch): ~0.15 s / ~0.27 s for a 5.7 s
#   clip on 2 threads (measured 2026-11-05). The binaries are wrappers around an on-demand
#   launcher, so sherpa-onnx is built and GC-rooted on the first call
#   (`modules/llm/asr.nix`). Models are plain ONNX files downloaded by hand, like the GGUFs.
#
# ### rag-search (vector search over notes)
#
# - CLI: `rag-search` (`~/.local/bin`, source in `packages/local-bin/bin/rag-search`).
# - Index: `~/.local/share/rag-notes/index.sqlite` (sqlite + float32 vectors, numpy cosine).
# - Pipeline: markdown chunking → `qwen3-embedding` (ollama, batched) → top-20 cosine → reranking
#   `bge-reranker-v2-m3` (llama-server `--rerank`, starts on demand for search, ctx 8192).
# - Answers: `--llm` via ollama; model — env `RAG_LLM_MODEL` (default
#   `qwen3-vl-abliterated:8b`, set in modules/user/nix-maid/cli/envs.nix).
#   The censored base tags were removed from the store; what is left:
#
# | Model                                | Size  | Role                                  |
# | ------------------------------------ | ----- | ------------------------------------- |
# | `qwen3-vl-abliterated:8b`            | 8.0GB | **default** — uncensored, fully on GPU |
# | `qwen3.8:27b`                        | 17GB  | kept for RU quality, spills to CPU    |
# | `qwen3-vl:8b`                        | 6.1GB | base vision tag, kept for now         |
# | `huihui_ai/qwen3-abliterated:30b-a3b`| 20GB  | uncensored, but 0.3 tok/s on 16GB     |
#
# One-off override: `RAG_LLM_MODEL=qwen3.8:27b rag-search search --llm "..."`
#
#     rag-search index                    # reindex (~227 files, ~2400 chunks, ~5 min)
#     rag-search search "how to set up tidal cycles" -n 5
#     rag-search search --llm "question" # answer from found fragments
#     rag-search status                   # index and reranker state
#
# ## Layout on disk
#
# - `/zero/ai/ollama` — Ollama model store (96 GB, 9 models: qwen3.8 27b, qwen3-vl 8b,
#   qwen3-vl-abliterated 8b, huihui abliterated 30b/35b/coder, qwen3-embedding, glm-ocr)
# - `/zero/ai/llama` — llama.cpp GGUFs (295 GB): qwen3-vl-8b, qwen3.8-27B,
#   the abliterated set (Gemma 26B IQ3, Qwen3.8-27B IQ3, Qwen3-VL-8B),
#   Qwen3.8-Flash-Next IQ3_S (78 GB, two shards
#   in `qwen38-flash-next-iq3s/`), the Lean provers (oprover,
#   deepseek-prover) and the small tiers (arduinollm, Spark). 34 GB of dead
#   weights (gpt-oss-20b, the 24 GB-box Gemma MXFP4 + its mmproj, Gemma E4B)
#   were deleted on 2026-11-05; gpt-oss-20b also left the catalog after it
#   failed the FP planning task, which now lives in `llmctl bench fp`.
#   Qwen3.6-35B, Qwen3.5-4B and MegaSciMoE-1.2B were deleted on 2026-11-08
#   (16 GB) and their router entries are gone with them. The gpt-oss-120b
#   MXFP4 weights (63 GB on disk) went the same way on 2026-11-10, when the
#   RAM tier left the fleet. The same pass removed the abliteration
#   experiment's Qwen3.5-VL base (52 GB), the censored Qwen3-VL-8B pair
#   (5.8 GB) and the unused DeepThought-STEM (5.3 GB) and qed-nano (4 GB).
# - `/zero/ai/image` — stable-diffusion.cpp models: SDXL base + VAE, FLUX.1-schnell q4_k + encoders
#   (created by tmpfiles)
# - `/zero/ai/embeddings` — RAG reranker GGUF (bge-reranker-v2-m3), future embedding GGUFs (created by
#   tmpfiles)
# - `/zero/ai/asr` — GigaAM-v3 and Parakeet-TDT-v3 ONNX models for sherpa-onnx (activation dir,
#   files downloaded by hand)
# - `/zero/ai/llama/{ocr,embed,fim}` — PaddleOCR-VL, Qwen3-Embedding-0.6B and the FIM coder GGUF .
# - `/zero/ai/glm52_i4` — empty directory; the colibrì int4 weights were deleted
#   2026-11-05 and `/zero/ai` is root-owned, so removing the directory itself
#   needs root
# - `/zero/ai/video/wangp` — WanGP (Wan2GP): git checkout, `venv` (torch+rocm7.1) and `ckpts/`
#   weights for video/image/audio/3D generation; launcher `wangp` in `packages/local-bin/bin`.
#   Created by the activation script, filled by hand (wheels and HF files, not a Nix package).
#
# ## Status on trantor
#
# - `features.llm.enable = true` (Ollama serving on 11434; every other engine starts manually)
# - Ollama: enabled; merged the orphaned 413 GB store (was nested under `/zero/ai/ollama/models/`)
#   into the active store — all 23 models now visible to `ollama list`, no re-download.
# - stable-diffusion.cpp: package added (Vulkan), models in `/zero/ai/image`.
# - Ports: 11434 (Ollama), 8000 (omnirouter), 8001 (piper TTS), 8002 (whisper STT),
#   8012 (llama-fim, user unit started by nvim), 8080 (llama-server, manual),
#   8013 (llama-rerank, also the rag-search default), 9292 (llama-swap API: chat, ocr, embed)

{
  neg,
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.ollama;

  # On-demand: the 548 MiB ROCm closure lives in a GC root, not in the system
  # image. The daemon runs as the `ollama` user, which cannot fetch the flake
  # (Nix refuses a git repository it does not own), so a oneshot running as the
  # main user materialises the root at a shared path and overrides ExecStart.
  # The launcher stays on PATH for the `ollama` CLI (its own root under $HOME).
  onDemand = config.lib.neg.onDemand pkgs;
  ollamaLauncher = onDemand {
    name = "ollama";
    attr = "ollama";
  };

  nixAppsRoot = "/var/lib/nix-apps";
  ollamaRoot = "${nixAppsRoot}/ollama";
  ollamaEnsure = pkgs.writeShellScriptBin "ollama-ensure" ''
    set -eu
    root=${lib.escapeShellArg ollamaRoot}
    if [ -e "$root" ]; then
      exit 0
    fi
    mkdir -p ${nixAppsRoot}
    rm -f "$root"
    out=$(${config.nix.package}/bin/nix build --no-link --print-out-paths 'git+file:///etc/nixos#ollama')
    ${config.nix.package}/bin/nix-store --add-root "$root" --indirect --realise "$out" >/dev/null
  '';
in
{
  imports = neg.importDir {
    dir = ./.;
    includeDirs = true;
  };
  config = lib.mkIf (config.lib.neg.enabled "llm") (
    lib.mkMerge [
      {
        services.ollama = {
          enable = lib.mkDefault true;
          package = ollamaLauncher; # CLI on PATH, built on first use
          # RX 9070 XT (Navi 48, gfx1201) — native ROCm support, no override
          user = "ollama";
          group = "ollama";
          modelsDir = "/zero/ai/ollama"; # existing 413G model store on the zero pool
        };

        systemd.services.ollama-ensure = {
          description = "Materialise the on-demand ollama root (GC root at /var/lib/nix-apps)";
          wantedBy = [ "multi-user.target" ];
          before = [ "ollama.service" ];
          after = [
            "network.target"
            "systemd-tmpfiles-setup.service"
          ];
          serviceConfig = {
            Type = "oneshot";
            User = config.lib.neg.mainUser;
          };
          script = "${ollamaEnsure}/bin/ollama-ensure";
        };

        systemd.services.ollama = {
          wants = [ "ollama-ensure.service" ];
          after = [ "ollama-ensure.service" ];
          serviceConfig.ExecStart = lib.mkForce "${ollamaRoot}/bin/ollama serve";
        };

        # Recursively fix ownership of the existing model store for the ollama
        # service user, and keep the main user in the ollama group so neg can
        # still manage model files.
        systemd.tmpfiles.rules = [
          # /var/lib/nix-apps itself is owned by modules/system/nix-apps.nix.
          "d /zero/ai 0755 root root -"
          "d /zero/ai/ollama 0770 ollama ollama -"
          "Z /zero/ai/ollama 0770 ollama ollama -"
          # llama-server (qwen3-vl GGUF) model store — main user manages files
          "d /zero/ai/llama 0755 ${config.users.main.name} ${config.users.main.name} -"
        ];
        # tmpfiles refuses paths under /zero/ai: /zero is owned by neg, so the
        # neg→root transition trips systemd's unsafe-path check and the rules
        # are skipped silently. Create the dirs via activation instead.
        system.activationScripts.ai-model-dirs = lib.stringAfter [ "users" ] ''
          install -d -o ${config.users.main.name} -g ${config.users.main.name} -m 0755 /zero/ai/image
          install -d -o ${config.users.main.name} -g ${config.users.main.name} -m 0755 /zero/ai/embeddings
          # music AI models (AMT weights, basic-pitch ONNX) — main user manages files
          install -d -o ${config.users.main.name} -g ${config.users.main.name} -m 0755 /zero/ai/music
          # image processing models (rembg BiRefNet/u2net, upscalers) — main user manages files
          install -d -o ${config.users.main.name} -g ${config.users.main.name} -m 0755 /zero/ai/imgproc
          # 3D generation weights (TripoSR) — main user manages files
          install -d -o ${config.users.main.name} -g ${config.users.main.name} -m 0755 /zero/ai/3d
          # whisperx STT/diarization models — main user manages files
          install -d -o ${config.users.main.name} -g ${config.users.main.name} -m 0755 /zero/ai/whisperx
          # OCR models (marker/surya) — main user manages files
          install -d -o ${config.users.main.name} -g ${config.users.main.name} -m 0755 /zero/ai/ocr
          # speech recognition models (GigaAM, Parakeet via sherpa-onnx) — main user manages files
          install -d -o ${config.users.main.name} -g ${config.users.main.name} -m 0755 /zero/ai/asr
          # WanGP app tree (checkout + venv + weights) — the `wangp` launcher runs
          # it; /zero/ai/video itself is root-owned, so only this leaf is ours.
          install -d -o ${config.users.main.name} -g ${config.users.main.name} -m 0755 /zero/ai/video/wangp
        '';
        users.users."${config.users.main.name}".extraGroups = lib.mkAfter [ "ollama" ];
      }
      (lib.mkIf cfg.enable {
        # nixpkgs sets DynamicUser=true unconditionally even with a static
        # user; force it off so the process runs as the real ollama user and
        # keeps stable ownership of /zero/ai/ollama.
        systemd.services.ollama.serviceConfig.DynamicUser = lib.mkForce false;
      })
    ]
  );
}
