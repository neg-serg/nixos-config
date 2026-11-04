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
# - colibrì (GLM-5.2 CPU engine) removed 2026-11-02; leftover weights: /zero/ai/glm52_i4
#
# ### llama-server (qwen3-vl vision, Vulkan/RADV)
#
# - Module: `modules/llm/llama-server.nix`
# - Engine: `pkgs.llama-cpp-vulkan`, GPU-backed (RX 9070 XT, RADV).
# - Role: local vision engine for the `vision-review` skill — images never leave the machine.
# - Model dir: `/zero/ai/llama` (qwen3-vl 30b/8b GGUF + mmproj) — on the `zero` ZFS pool, never on
#   system disks.
# - Deliberately not auto-started; start on demand:
#       systemctl start llama-server          # 30b on 127.0.0.1:8080
#       /zero/ai/llama/start-llama-server.sh  # same, manual run (optional port/model args)
#
# ### llama-swap (one OpenAI-compatible endpoint, 127.0.0.1:9292)
#
# - Module: `modules/llm/llama-swap.nix`; the `model` field selects a backend,
#   one model is resident at a time (16 GB VRAM, ~3.5 GB of it is the desktop).
# - Idle backends are unloaded after `globalTTL` 60 s, and the game guard
#   unloads them at once when a game starts.
# - Only models that fit the card are exposed here. `qwen3-vl-30b` (18 GB) and
#   Flash-Next (111 GB, CPU-MoE) were removed from the router — they stay
#   available as manual `llama-server` / `llama-server-flash-next` units.
# - Vulkan (`pkgs.llama-cpp-vulkan`) is the fast path for Gemma 4 on gfx1201:
#   the same weights run 3-10x faster than through ollama's ROCm build, and
#   `--cpu-moe` is a trap here (3-8 tok/s, expert weights become the bottleneck).
# - Models (quant, measured VRAM/speed on 2026-11-04):
#
#   | model        | weights                                  | ctx | VRAM  | tok/s |
#   | ------------ | ---------------------------------------- | --- | ----- | ----- |
#   | gemma4-26b   | gemma-4-26B-A4B-it-UD-Q3_K_XL (MoE)      | 64k | 16.0G | 30-40 |
#   | gemma4-12b   | gemma-4-12B-it-qat-UD-Q4_K_XL + mmproj   | 32k | 11.3G | 29    |
#   | gpt-oss-20b  | gpt-oss-20b-abliterated MXFP4            | 32k | 15.8G | 75-85 |
#   | qwen3.8-4b   | Qwen3.8-4B-Distill-Heretic Q4 + mmproj   | 32k | 4.5G  | 56-60 |
#
# - `gpt-oss-20b-abliterated` needs `--reasoning-effort low`: at the default
#   effort it spends the whole token budget on reasoning and returns empty
#   content. With low effort it keeps tools, JSON and arithmetic intact.
#
# - `qwen3.8-4b-abliterated` is the uncensored 4B tier (text + vision, thinking
#   off). It handles translation, summaries, JSON extraction, classification and
#   short creative text; it fails simple arithmetic and invents facts, so keep
#   reasoning, coding and factual work on the bigger models.
# - `gemma4-26b` runs Q3_K_XL, not the QAT Q4: the desktop session holds
#   ~3.5 GB, so Q4 (13.2 GiB of weights) has no room left after a swap and the
#   Vulkan backend dies on the first request; Q3 spills ~1 GB into GTT and
#   stays up. It is text-only on purpose: the 1.2 GB projector does not fit;
#   `gemma4-12b` takes images.
# - The Gemma 4, gpt-oss and 4B commands start with `--fit off`. Auto-fit reads
#   the VRAM of the model being swapped out as free, offloads a few layers, and
#   gemma4 then crashes on the first request; a deterministic full load either
#   fits or fails loudly.
# - The ollama copies (`gemma4:26b` 17 GB, `gemma4:12b` 7.6 GB) stay for
#   `rag-search`, but their ROCm path is slow (2.5 / 8.8 tok/s); for interactive
#   work use the llama-swap names above.
#
# ### vLLM (OpenAI-compatible server, ROCm)
#
# - Module: `modules/llm/vllm.nix`; package: `pkgs.vllmRocmEnv`
#   (`packages/vllm-rocm/default.nix` — vLLM 0.24.0 built against the ROCm torch 2.12.0
#   closure of `torch-rocm`, gfx1201).
# - Role: the throughput/high-concurrency server (continuous batching, paged attention,
#   OpenAI-compatible API) — the Ollama/llama.cpp alternatives here are single-stream and
#   the colibrì engine is disk-bound. Same weights, much faster under parallel load.
# - Built from source, no binary cache for the HIP kernels: the first build takes tens of
#   minutes, everything after that is store reuse. Coherent GPU kernel changes in
#   `packages/vllm-rocm/default.nix`'s header.
# - Model store: `/zero/ai/vllm` (HF cache + Triton kernel cache) — never on system disks.
# - VRAM is shared with the desktop session and Ollama (~5.5 GB in use at idle), so
#   `services.vllm.gpuMemoryUtilization` defaults to 0.6 instead of vLLM's 0.92 — at 0.92 the
#   engine aborts at startup ("free memory … less than desired"). `ollama stop <model>` before
#   raising it.
# - Deliberately not auto-started:
#       systemctl start vllm                  # service model on 127.0.0.1:8004
#       vllm serve Qwen/Qwen3-8B-AWQ --port 8004   # one-off, any model
#       curl http://127.0.0.1:8004/v1/models
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
# - Two engines: classic **tesseract** (eng+rus, fast) and local **neural** OCR via Ollama's
#   `qwen3-vl:8b` (default; override with `PIC_OCR_NN_MODEL`). Neural images never leave the machine.
# - Usage: `pic-ocr [--engine=nn|tesseract|menu] IMAGE`; with no IMAGE it captures a region (`slurp`).
#   Result goes to the clipboard + `notify-send`.
# - Wired into the quickshell **ScreenshotToast**: after a Hyprland screenshot (`M4+SHIFT+R`,
#   `M4+SHIFT+CTRL+R`) the toast offers **OCR** (tesseract) and **OCR NN** (neural) buttons.
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
# - Reranker: `bge-reranker-v2-m3-Q4_K_M.gguf` in `/zero/ai/embeddings` — served via llama.cpp
#   `llama-server --rerank` or used directly with llama.cpp's embedding CLI.
# - Both are multilingual (RU/EN); reranker should be the top-k filter before LLM context assembly.
#
# ### rag-search (vector search over notes)
#
# - CLI: `rag-search` (`~/.local/bin`, source in `packages/local-bin/bin/rag-search`).
# - Index: `~/.local/share/rag-notes/index.sqlite` (sqlite + float32 vectors, numpy cosine).
# - Pipeline: markdown chunking → `qwen3-embedding` (ollama, batched) → top-20 cosine → reranking
#   `bge-reranker-v2-m3` (llama-server `--rerank`, starts on demand for search, ctx 8192).
# - Answers: `--llm` via ollama; model — env `RAG_LLM_MODEL` (default `qwen3.5:27b`, set in
#   modules/user/nix-maid/cli/envs.nix). Options (all already in the ollama store):
#
# | Model                          | Size                     | Role                                   |
# | ------------------------------ | ------------------------ | -------------------------------------- |
# | `qwen3.5:27b`                  | 17 GB                    | **default** — quality/speed/RU balance |
# | `gemma4:12b`                   | 7.6 GB                   | fits VRAM, but ollama/ROCm is slow (~9 tok/s) |
# | `gemma4:26b`                   | 17 GB                    | Gemma 4 quality, 2.5 tok/s (offload)   |
# | `qwen3:32b`                    | 20 GB                    | fallback, slightly older               |
# | `llama3.3:70b-instruct-q5_K_M` | 49 GB (CPU)              | max quality, ~2-4 tok/s                |
# | `qwen3:235b-a22b`              | 142 GB (CPU/RAM MoE)     | heaviest, ~1 tok/s — for the future    |
# | `qwen3.5:122b`                 | 76 GB (122B-A10B MoE Q4) | big new-gen, ~2-4 tok/s (downloaded)   |
#
# One-off override: `RAG_LLM_MODEL=llama3.3:70b-instruct-q5_K_M rag-search search --llm "..."`
#
#     rag-search index                    # reindex (~227 files, ~2400 chunks, ~5 min)
#     rag-search search "how to set up tidal cycles" -n 5
#     rag-search search --llm "question" # answer from found fragments
#     rag-search status                   # index and reranker state
#
# ## Layout on disk
#
# - `/zero/ai/ollama` — Ollama model store (437 GB, 23 models: qwen3 32b/235b-a22b, qwen3-coder 30b,
#   qwen2.5-coder, qwen3-coder-next, deepcoder, devstral, qwq, gemma4, llama3.3 70b, qwen3.5 27b,
#   qwen3-embedding, glm-ocr, abliterated variants, qwen3-vl/qwen2.5vl, …)
# - `/zero/ai/llama` — llama.cpp GGUFs (~220 GB, Flash-Next alone is 104 GB):
#   qwen3-vl vision, qwen3.8-27B, GLM-4.7-Flash, Gemma 4 26B Q3 / 12B QAT,
#   gpt-oss-20b, Spark-X2.5, Flash-Next
# - `/zero/ai/image` — stable-diffusion.cpp models: SDXL base + VAE, FLUX.1-schnell q4_k + encoders
#   (created by tmpfiles)
# - `/zero/ai/embeddings` — RAG reranker GGUF (bge-reranker-v2-m3), future embedding GGUFs (created by
#   tmpfiles)
# - `/zero/ai/glm52_i4` — leftover colibrì int4 model (~384 GB, 144 shards); the engine was removed
#   2026-11-02, the weights stay on disk until they are deleted by hand
# - `/zero/ai/vllm` — vLLM: HF cache (`hf/`, weights + tokenizers), download dir (`hub/`) and the
#   Triton kernel cache (`cache/`), created by the activation script
#
# ## Status on trantor
#
# - `features.llm.enable = true` (Ollama serving on 11434; every other engine starts manually)
# - Ollama: enabled; merged the orphaned 413 GB store (was nested under `/zero/ai/ollama/models/`)
#   into the active store — all 23 models now visible to `ollama list`, no re-download.
# - stable-diffusion.cpp: package added (Vulkan), models in `/zero/ai/image`.
# - Ports: 11434 (Ollama), 8000 (omnirouter), 8001 (piper TTS), 8002 (whisper STT), 8004 (vLLM,
#   manual), 8080 (llama-server, manual)

{
  neg,
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.ollama;
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
          package = pkgs.ollama-rocm;
          # RX 9070 XT (Navi 48, gfx1201) — native ROCm support, no override
          user = "ollama";
          group = "ollama";
          modelsDir = "/zero/ai/ollama"; # existing 413G model store on the zero pool
        };

        # Recursively fix ownership of the existing model store for the ollama
        # service user, and keep the main user in the ollama group so neg can
        # still manage model files.
        systemd.tmpfiles.rules = [
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
          install -d -o ${config.users.main.name} -g ${config.users.main.name} -m 0755 /zero/ai/glm52_i4
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
          # vLLM weights, HF cache and Triton kernel cache — main user manages files
          install -d -o ${config.users.main.name} -g ${config.users.main.name} -m 0755 /zero/ai/vllm
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
