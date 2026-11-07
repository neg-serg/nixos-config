# UI-TARS-1.5-7B (Apache-2.0) — Qwen2.5-VL based GUI agent. It consumes a
# screenshot plus the COMPUTER_USE prompt and returns Thought/Action with
# absolute coordinates; it does not execute anything itself. Q6_K (6.25 GB)
# plus the f16 vision projector (1.35 GB) fit the 16 GB card next to the
# desktop; Q8 would leave too little headroom with a 32k KV cache.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "llm";
  modelDir = "/zero/ai/llama";
  llamaVulkan = lib.getExe' pkgs.llama-cpp-vulkan "llama-server";
in
{
  config = lib.mkIf enabled {
    services.llama-swap.settings.models."ui-tars-1.5-7b" = {
      cmd = ''
        ${llamaVulkan} --device Vulkan0 \
          -m ${modelDir}/uitars/UI-TARS-1.5-7B.Q6_K.gguf \
          --mmproj ${modelDir}/uitars/UI-TARS-1.5-7B.mmproj-f16.gguf \
          --host 127.0.0.1 --port ''${PORT} \
          -c 32768 -np 1 --flash-attn on --fit off --jinja \
          --cache-type-k q8_0 --cache-type-v q8_0 -ub 1024 \
          --image-max-tokens 16384
      '';
      aliases = [
        "uitars"
        "ui-tars"
      ];
      ttl = 600;
    };
  };
}
