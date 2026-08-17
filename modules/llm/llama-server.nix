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

  modelFile =
    if cfg.model == "30b" then
      "qwen3-vl-30b-a3b-instruct-q4_k_m.gguf"
    else
      "qwen3-vl-8b-instruct-q4_k_m.gguf";
  mmprojFile =
    if cfg.model == "30b" then
      "mmproj-qwen3-vl-30b-a3b-f16.gguf"
    else
      "mmproj-qwen3-vl-8b-f16.gguf";
in
{
  options.services.llama-server = {
    # Present by default when the llm feature is on; the unit is never
    # auto-started (no wantedBy) — start it manually when needed.
    enable = (lib.mkEnableOption ''
      llama-server — local vision engine for the vision-review skill
      (qwen3-vl via llama.cpp, Vulkan/RADV backend).

      Deliberately NOT started by any target: enable it manually with
      `systemctl start llama-server` whenever you need image analysis.
    '') // {
      default = true;
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port for the OpenAI-compatible endpoint (bound to 127.0.0.1).";
    };

    model = lib.mkOption {
      type = lib.types.enum [
        "30b"
        "8b"
      ];
      default = "30b";
      description = ''
        Which GGUF to serve: `30b` (qwen3-vl-30b-a3b, default) or `8b`
        (qwen3-vl-8b). Files must exist in `/zero/ai/llama/`.
      '';
    };
  };

  config = lib.mkIf (enabled && cfg.enable) {
    systemd.services.llama-server = {
      description = "llama-server Vulkan (qwen3-vl vision, vision-review backend)";
      # No wantedBy/requiredBy: manual start only (`systemctl start llama-server`).
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        User = config.users.main.name;
        # GPU access for the Vulkan (RADV) backend.
        SupplementaryGroups = [
          "render"
          "video"
        ];
        ExecStart = ''
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
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
