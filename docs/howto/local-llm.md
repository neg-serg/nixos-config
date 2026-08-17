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
- Model dir: `/zero/ai/llama` (qwen3-vl 30b/8b GGUF + mmproj) — on the `zero` ZFS pool,
  never on system disks.
- Deliberately not auto-started; start on demand:
  ```bash
  systemctl start llama-server          # 30b on 127.0.0.1:8080
  /zero/ai/llama/start-llama-server.sh  # same, manual run (optional port/model args)
  ```

### voxinput (voice → text)

- Module: `modules/llm/pkgs.nix`
- Installed when `features.llm.enable` — voice-to-text via LocalAI/OpenAI-compatible endpoint +
  `dotool`/`uinput`.

### local-ai user service (fallback)

- `modules/user/nix-maid/sys/user-services.nix` — user-level Ollama fallback for hosts **without**
  the system `services.ollama` (it would conflict on port 11434). On `odin` the system service is
  enabled, so the user service stays off. Models also on `/zero/ai/ollama` / `/zero/ai/localai`.

## Layout on disk

- `/zero/ai/ollama` — Ollama model store (413 GB, exists)
- `/zero/ai/llama` — llama-server (qwen3-vl) GGUF models (24 GB, exists)
- `/zero/ai/glm52_i4` — colibrì int4 model (~370 GB, needs download)
- `/zero/ai/localai` — LocalAI model dir (fallback path)

## Status on odin

- `features.llm.enable = true`, `services.colibri.enable = true`
- Ollama: enabled, serves existing 413 GB store
- colibrì: engine installed; model not downloaded yet
- Ports: 11434 (Ollama), 8000 (colibri serve, only if enabled)
