# Local LLM stack

How the local neural-network stack on the `odin` host works, what is enabled, and how to operate it.

Everything below is gated on a single feature flag:

```nix
features.llm.enable = true;
```

defined in `modules/features/misc.nix` (default `false`) and enabled for `odin` in
`hosts/odin/default.nix`.

## Components

### Ollama (LLM serving, ROCm-accelerated)

- Module: `modules/llm/{default,ollama}.nix`
- Package: `pkgs.ollama-rocm` (ROCm build)
- Bind: `0.0.0.0:11434` (firewall opened)
- Model store: `/zero/ai/ollama` — lives on the `zero` ZFS pool, never on system disks. An existing
  413 GB store (18 models: qwen3 32b/235b, llama3.3 70b, qwen3-coder, devstral, qwq, abliterated
  variants, …) is already in place; no re-download needed.
- Service user: `ollama` (static user, `DynamicUser = false` so ownership of the store stays
  stable). `neg` is in the `ollama` group and can manage model files.
- tmpfiles ensure `/zero/ai/ollama` is `0770 ollama:ollama` (with `Z` recursive fixup at boot).
- GPU: RX 9070 XT (Navi 48, gfx1201). The pinned nixpkgs' ROCm ships gfx1201 code objects, so no
  `HSA_OVERRIDE_GFX_VERSION` is needed.

CLI:

```bash
ollama list
ollama pull qwen3:32b
ollama run qwen3:32b
```

### colibrì (GLM-5.2 744B MoE engine, CPU-only)

- Module: `modules/llm/colibri.nix`
- Engine: pure C, streams experts from disk; no GPU required.
- Expected performance on this machine (9950X3D, AVX-512+VNNI, 60 GB RAM, PCIe 5.0 NVMe): ~0.8–1.6
  tok/s with warm cache + MTP.
- Model dir: `/zero/ai/glm52_i4` (~370 GB, int4). **Not downloaded yet** —
  `services.colibri.enable = true` installs the engine + `coli` CLI, but the serve unit stays off
  until the model exists.
- Defaults: `arch = "native"`, `ramBudget = 45`, settings
  `DIRECT=1 PIPE_WORKERS=16 PREFETCH=1 MTP=3`.

Get the model (one-time, ~370 GB):

```bash
# pre-converted int4 weights:
# https://huggingface.co/mateogrgic/GLM-5.2-colibri-int4-with-int8-mtp
# or convert yourself after installing colibri:
coli convert --model /path/to/GLM-5.2-weights
```

Serve OpenAI-compatible API (after the model is present):

```nix
services.colibri = {
  enable = true;
  serve = {
    enable = true;
    port = 8000;            # default
    # apiKeyFile = "/run/secrets/...";  # optional auth
  };
};
```

### llama-server (qwen3-vl vision, Vulkan/RADV)

- Module: `modules/llm/llama-server.nix`
- Engine: `pkgs.llama-cpp-vulkan`, GPU-backed (RX 9070 XT, RADV).
- Role: local vision engine for the `vision-review` skill — images never leave the machine.
- Model dir: `/zero/ai/llama` (qwen3-vl 30b/8b GGUF + mmproj) — on the `zero` ZFS pool, never on
  system disks.
- Deliberately not auto-started; start on demand:
  ```bash
  systemctl start llama-server          # 30b on 127.0.0.1:8080
  /zero/ai/llama/start-llama-server.sh  # same, manual run (optional port/model args)
  ```

### voxinput (voice → text)

- Module: `modules/llm/pkgs.nix`
- Installed when `features.llm.enable` — voice-to-text via LocalAI/OpenAI-compatible endpoint +
  `dotool`/`uinput`.

### pic-ocr (screenshot → text, engine choice)

- Script: `packages/local-bin/bin/pic-ocr` (installed to `~/.local/bin`).
- Two engines: classic **tesseract** (eng+rus, fast) and local **neural** OCR via Ollama's
  `qwen3-vl:8b` (default; override with `PIC_OCR_NN_MODEL`). Neural images never leave the machine.
- Usage: `pic-ocr [--engine=nn|tesseract|menu] IMAGE`; with no IMAGE it captures a region (`slurp`).
  Result goes to the clipboard + `notify-send`.
- Wired into the quickshell **ScreenshotToast**: after a Hyprland screenshot (`M4+SHIFT+R`,
  `M4+SHIFT+CTRL+R`) the toast offers **OCR** (tesseract) and **OCR NN** (neural) buttons.

### local-ai user service (fallback)

- `modules/user/nix-maid/sys/user-services.nix` — user-level Ollama fallback for hosts **without**
  the system `services.ollama` (it would conflict on port 11434). On `odin` the system service is
  enabled, so the user service stays off. Models also on `/zero/ai/ollama` / `/zero/ai/localai`.

### stable-diffusion.cpp (text-to-image, Vulkan)

- Package: `pkgs.stable-diffusion-cpp` overridden with `vulkanSupport = true` (RADV on the RX 9070
  XT). In this nixpkgs rev the binaries are `sd-cli`/`sd-server` (not `sd` — no conflict with the
  Rust `sd` sed replacement).
- Role: fast local T2I without touching ComfyUI/ROCm — pure Vulkan, fits the "Vulkan-first"
  preference.
- Model dir: `/zero/ai/image` — SDXL base checkpoint + VAE, FLUX.1-schnell (GGUF q4_k) +
  clip_l/t5xxl/ae.
- Binary: `sd-cli`. Examples:

```bash
# SDXL (checkpoint carries its own text encoders)
sd-cli -m /zero/ai/image/sd_xl_base_1.0.safetensors --vae /zero/ai/image/sdxl_vae.safetensors \
   -H 1024 -W 1024 -p "a lovely cat" -v

# FLUX.1-schnell (GGUF unet + separate encoders; cfg-scale 1, 4 steps)
sd-cli --diffusion-model /zero/ai/image/flux1-schnell-q4_k.gguf --vae /zero/ai/image/ae.safetensors \
   --clip_l /zero/ai/image/clip_l.safetensors --t5xxl /zero/ai/image/t5xxl_fp8_e4m3fn.safetensors \
   -p "a lovely cat" --cfg-scale 1.0 --sampling-method euler --steps 4 -v --clip-on-cpu
```

- GPU notes: q4_k GGUF ≈ 6.4 GB in VRAM (fits 16 GB alongside the fp8 t5xxl); q8_0 ≈ 12 GB — only
  with a lighter t5. FLUX needs `--cfg-scale 1.0`; SDXL default cfg ~6.

### Embeddings & reranker (RAG)

- Embeddings: **qwen3-embedding** (already in the ollama store, Q4_K_M, 4096 dims) — use via
  `ollama pull qwen3-embedding` + `POST /api/embed` or OpenAI-compatible `/v1/embeddings`.
- Reranker: `bge-reranker-v2-m3-Q4_K_M.gguf` in `/zero/ai/embeddings` — served via llama.cpp
  `llama-server --rerank` or used directly with llama.cpp's embedding CLI.
- Both are multilingual (RU/EN); reranker should be the top-k filter before LLM context assembly.

## Layout on disk

- `/zero/ai/ollama` — Ollama model store (437 GB, 23 models: qwen3 32b/235b-a22b, qwen3-coder 30b,
  qwen2.5-coder, qwen3-coder-next, deepcoder, devstral, qwq, gemma4, llama3.3 70b, qwen3.5 27b,
  qwen3-embedding, glm-ocr, abliterated variants, qwen3-vl/qwen2.5vl, …)
- `/zero/ai/llama` — llama-server (qwen3-vl) GGUF models (24 GB, exists)
- `/zero/ai/image` — stable-diffusion.cpp models: SDXL base + VAE, FLUX.1-schnell q4_k + encoders
  (created by tmpfiles)
- `/zero/ai/embeddings` — RAG reranker GGUF (bge-reranker-v2-m3), future embedding GGUFs (created by
  tmpfiles)
- `/zero/ai/glm52_i4` — colibrì int4 model (~370 GB, needs download)
- `/zero/ai/localai` — LocalAI model dir (fallback path)

## Status on odin

- `features.llm.enable = true`, `services.colibri.enable = true`
- Ollama: enabled; merged the orphaned 413 GB store (was nested under `/zero/ai/ollama/models/`)
  into the active store — all 23 models now visible to `ollama list`, no re-download.
- stable-diffusion.cpp: package added (Vulkan), models downloaded to `/zero/ai/image` (pending
  rebuild).
- colibrì: engine installed; model not downloaded yet
- Ports: 11434 (Ollama), 8000 (colibri serve, only if enabled)
