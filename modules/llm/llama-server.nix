{
  config,
  lib,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "llm";
  cfg = config.services.llama-server;

  # Models live on the zero ZFS pool (downloaded manually, not in the store —
  # they are multi-GB and GC would not help). Never on system disks.
  modelDir = "/zero/ai/llama";

  # The 30B vision weights (18 GB) were removed on 2026-11-06: they do not fit
  # the 16 GB card next to the desktop. The censored Qwen3-VL-8B pair went with
  # the 2026-11-10 weight cleanup, so the unit serves the abliterated 8B pair
  # that the router already uses — the only vision files left on disk. The 27B
  # `vision` tier is router-only (it needs the swap and the 32k KV budget).
  modelFile = "abliterated/Qwen3-VL-8B-abliterated-Q4_K_M.gguf";
  mmprojFile = "abliterated/mmproj-qwen3-vl-8b-ablit-f16.gguf";
in
{
  options.services.llama-server = {
    # Present by default when the llm feature is on; the unit is never
    # auto-started (no wantedBy) — start it manually when needed.
    enable =
      (lib.mkEnableOption ''
        llama-server — local vision engine for the vision-review skill
        (qwen3-vl via llama.cpp, Vulkan/RADV backend).

        Deliberately NOT started by any target: enable it manually with
        `systemctl start llama-server` whenever you need image analysis.
      '')
      // {
        default = true;
      };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port for the OpenAI-compatible endpoint (bound to 127.0.0.1).";
    };

  };

  config = lib.mkIf (enabled && cfg.enable) {
    systemd.services.llama-server = config.lib.neg.llamaServer.mkService {
      description = "llama-server Vulkan (qwen3-vl vision, vision-review backend)";
      user = config.users.main.name;
      execStart = ''
        ${pkgs.llama-cpp-vulkan}/bin/llama-server \
          --device Vulkan0 \
          -m ${modelDir}/${modelFile} \
          --mmproj ${modelDir}/${mmprojFile} \
          --port ${toString cfg.port} \
          --host 127.0.0.1 \
          -c 8192 \
          -np 1 \
          --log-disable
      '';
    };
  };
}
