# GUI-agent VLMs (Apache-2.0 / Qwen licence) — the small computer-use tier
# next to `uitars.nix`. Each takes a screenshot plus an instruction and
# returns an action (usually `click(start_box='<|box_start|>(x,y)<|box_end|>')`),
# absolute pixel coordinates in the screenshot; none of them executes anything.
# They are the cheap/fast options behind UI-TARS-1.5-7B: 2-4B Qwen-VL
# derivatives, ~3 GB each with the projector, so the whole tier swaps in
# seconds and leaves the 16 GB card to the desktop.
#
# Numbers from the cards (UI-localization, not our screen): Holo2-4B
# ScreenSpot-Pro 57.2 / WebClick 88.8 / ScreenSpot-v2 93.2; Holo1.5-3B
# 51.5 / 81.5 / 91.7; GUI-Owl-1.5-4B and UI-TARS-2B are not comparable here
# (different harnesses). Serving all four at Q4_K_M + a Q8 projector keeps
# the comparison honest: same weights class, same llama.cpp, same prompt.
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
    services.llama-swap.settings.models = {
      # Holo2-4B — H Company's navigation/computer-use model on Qwen3-VL-4B.
      # The card puts it on WebVoyager/WebArena/OSWorld/AndroidWorld and on the
      # localization benchmarks; 4B is the smallest fully-open member.
      "holo2-4b" = {
        aliases = [
          "holo2"
        ];
        ttl = 600;
        cmd = ''
          ${llamaVulkan} --device Vulkan0 \
            -m ${modelDir}/gui/Holo2-4B.Q4_K_M.gguf \
            --mmproj ${modelDir}/gui/Holo2-4B.mmproj-Q8_0.gguf \
            --host 127.0.0.1 --port ''${PORT} \
            -c 16384 -np 1 --flash-attn on --fit off --jinja \
            --cache-type-k q8_0 --cache-type-v q8_0 -ub 1024 \
            --image-max-tokens 8192
        '';
      };

      # Holo1.5-3B — the previous generation at 3B, Qwen2.5-VL based and
      # natively 3840x2160; the card's 3B row is the best small localizer it
      # published, so it stays as the "fast but older" reference point.
      "holo1.5-3b" = {
        aliases = [
          "holo3b"
          "holo1.5"
        ];
        ttl = 600;
        cmd = ''
          ${llamaVulkan} --device Vulkan0 \
            -m ${modelDir}/gui/Holo1.5-3B.Q4_K_M.gguf \
            --mmproj ${modelDir}/gui/Holo1.5-3B.mmproj-Q8_0.gguf \
            --host 127.0.0.1 --port ''${PORT} \
            -c 16384 -np 1 --flash-attn on --fit off --jinja \
            --cache-type-k q8_0 --cache-type-v q8_0 -ub 1024 \
            --image-max-tokens 8192
        '';
      };

      # GUI-Owl-1.5-4B — mPLUG's end-to-end GUI agent (Instruct variant, no
      # thinking), Qwen3-VL-4B base. Same prompt-as-a-graph family as
      # Mobile-Agent, so it is the third opinion on grounding.
      "gui-owl-4b" = {
        aliases = [
          "guiowl"
          "gui-owl"
        ];
        ttl = 600;
        cmd = ''
          ${llamaVulkan} --device Vulkan0 \
            -m ${modelDir}/gui/GUI-Owl-1.5-4B-Instruct.Q4_K_M.gguf \
            --mmproj ${modelDir}/gui/GUI-Owl-1.5-4B-Instruct.mmproj-Q8_0.gguf \
            --host 127.0.0.1 --port ''${PORT} \
            -c 16384 -np 1 --flash-attn on --fit off --jinja \
            --cache-type-k q8_0 --cache-type-v q8_0 -ub 1024 \
            --image-max-tokens 8192
        '';
      };

      # UI-TARS-2B-SFT — the 2B generation of the model already served at 7B.
      # It is the speed floor: half the weights of the 7B, and the weakest
      # localizer in this set (the card's own numbers put the 2B well under
      # the 7B), kept to show what "fast" costs in accuracy.
      "ui-tars-2b" = {
        aliases = [
          "uitars2b"
          "tars2b"
        ];
        ttl = 600;
        cmd = ''
          ${llamaVulkan} --device Vulkan0 \
            -m ${modelDir}/gui/UI-TARS-2B-SFT.Q4_K_M.gguf \
            --mmproj ${modelDir}/gui/UI-TARS-2B-SFT.mmproj-fp16.gguf \
            --host 127.0.0.1 --port ''${PORT} \
            -c 16384 -np 1 --flash-attn on --fit off --jinja \
            --cache-type-k q8_0 --cache-type-v q8_0 -ub 1024 \
            --image-max-tokens 8192
        '';
      };
    };
  };
}
