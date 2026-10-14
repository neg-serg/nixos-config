# llama-swap — one OpenAI-compatible endpoint in front of the local model
# stack. The `model` field of a request selects the backend: llama-swap starts
# it (or proxies to it) and shuts the previously running one down; an idle
# backend is unloaded after `ttl`. This replaces starting llama-server
# (Vulkan, vision) / llama-server-flash-next (ROCm) by hand and juggling ports;
# clients use http://127.0.0.1:9292/v1.
#
# The per-model units stay available for manual use, but do not run them while
# llama-swap owns the GPU (16 GB VRAM, one big model at a time).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "llm";

  # Models live on the zero ZFS pool, never in the store (multi-GB files).
  modelDir = "/zero/ai/llama";
  llamaVulkan = lib.getExe' pkgs.llama-cpp-vulkan "llama-server";
  llamaRocm = lib.getExe' pkgs.llama-cpp-qwen4exp-rocm "llama-server";

  # Vision models (Vulkan/RADV): flags mirror modules/llm/llama-server.nix.
  vision30b = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/qwen3-vl-30b-a3b-instruct-q4_k_m.gguf \
      --mmproj ${modelDir}/mmproj-qwen3-vl-30b-a3b-f16.gguf \
      --host 127.0.0.1 --port ''${PORT} -c 8192 -np 1
  '';
  vision8b = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/qwen3-vl-8b-instruct-q4_k_m.gguf \
      --mmproj ${modelDir}/mmproj-qwen3-vl-8b-f16.gguf \
      --host 127.0.0.1 --port ''${PORT} -c 8192 -np 1
  '';

  # Flash-Next (ROCm, qwen4exp): flags mirror llama-server-flash-next.nix —
  # PLE tensors on CPU, 8 GPU layers (verified safe on the RX 9070 XT), mmap.
  flashNext = ''
    ${llamaRocm} --device ROCm0 \
      --model ${modelDir}/UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      --load-mode mmap --fit off --n-gpu-layers 8 --ctx-size 8192 \
      --flash-attn off --cache-type-k f16 --cache-type-v f16 --cpu-moe \
      -ot 'blk\.[0-9]+\.ple_value=CPU,blk\.[0-9]+\.ple_key=CPU' \
      --jinja --chat-template-kwargs '{"reasoning_effort":"low"}'
  '';

  ollamaUrl = "http://127.0.0.1:11434";
in
{
  services.llama-swap = lib.mkIf enabled {
    enable = lib.mkDefault true;
    listenAddress = "127.0.0.1";
    port = 9292;

    settings = {
      # Flash-Next mmaps a 111 GB GGUF (-ngl 8); a cold load can take minutes.
      healthCheckTimeout = 600;
      models = {
        "qwen3-vl-30b" = {
          cmd = vision30b;
          aliases = [ "vision" ];
          ttl = 900;
        };
        "qwen3-vl-8b" = {
          cmd = vision8b;
          aliases = [ "vision-8b" ];
          ttl = 900;
        };
        "qwen3.8-flash-next" = {
          cmd = flashNext;
          ttl = 900;
        };

      };

      # Ollama runs its own loading; expose it as a peer. Peer models are
      # addressable as `ollama/<name>`, and unqualified when unique.
      peers.ollama = {
        proxy = ollamaUrl;
        models = [
          "llama3.2:1b" # small smoke-test model
          "qwen3.8:27b"
          "qwen3.8:27b-plain"
          "qwen3:8b-ru"
          "gemma4:12b"
        ];
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
}
