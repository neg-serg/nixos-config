##
# Module: llm/rerank
# Purpose: standalone cross-encoder reranker endpoint for RAG and agents —
# llama.cpp with bge-reranker-v2-m3 on the dGPU, port 8013.
#
# Why a service and not a llama-swap slot: llama-swap proxies the
# chat/embeddings endpoints but does not route /v1/rerank (the request hangs,
# measured), and Qwen3-Reranker is a causal LM that scores yes/no through its
# chat template, so llama.cpp's rank pooling produces meaningless scores for
# it. bge-reranker-v2-m3 (Apache-2.0, Q4_K_M GGUF on /zero) is the
# llama.cpp-compatible choice: six documents rank in ~30 ms on the card
# against ~12 s on the CPU.
#
# Always on (unlike the FIM unit): a RAG caller should not pay a model load
# per query, the model is 438 MB, and llama.cpp keeps it in VRAM only while
# idle memory allows. rag-search points at this port by default and still
# falls back to spawning its own instance when the service is down.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "llm";
  llamaVulkan = lib.getExe' pkgs.llama-cpp-vulkan "llama-server";
  modelDir = "/zero/ai/embeddings";
in
{
  options.services.llama-rerank = {
    enable =
      (lib.mkEnableOption ''
        llama-server reranker — bge-reranker-v2-m3 on the dGPU (port 8013) for
        rag-search and any OpenAI-compatible /v1/rerank caller.
      '')
      // {
        default = true;
      };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8013;
      description = "Port for /v1/rerank and /health (bound to 127.0.0.1).";
    };
    model = lib.mkOption {
      type = lib.types.str;
      default = "${modelDir}/bge-reranker-v2-m3-Q4_K_M.gguf";
      description = "Reranker GGUF on the zero pool (downloaded by hand).";
    };
  };

  config = lib.mkIf (enabled && config.services.llama-rerank.enable) {
    systemd.services.llama-rerank = config.lib.neg.systemdUser.mkSystemService {
      description = "llama-server reranker (bge-reranker-v2-m3, dGPU)";
      presets = [ "restartOnFailure" ];
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "simple";
        User = config.users.main.name;
        SupplementaryGroups = [
          "render"
          "video"
        ];
        ExecStart = ''
          ${llamaVulkan} --device Vulkan0 \
            -m ${config.services.llama-rerank.model} \
            -ngl 99 -c 8192 -np 1 --reranking --pooling rank \
            --host 127.0.0.1 --port ${toString config.services.llama-rerank.port}
        '';
        # The preset supplies Restart=on-failure; the delay stays here.
        RestartSec = 5;
      };
    };
  };
}
