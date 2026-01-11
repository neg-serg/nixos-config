##
# Module: servers/vllm
# Purpose: vLLM is a high-throughput and memory-efficient inference and serving engine for LLMs.
# Key options: profiles.services.vllm (enable, model, httpPort, dataDir, gpuMemoryUtilization, maxModelLen, maxNumSeqs, servedModelName).
# Dependencies: virtualisation.oci-containers (backend = podman).
{
  lib,
  config,
  ...
}:
let
  cfg = config.profiles.services.vllm;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;
in
{
  options.profiles.services.vllm = {
    enable = mkEnableOption "vLLM (vllm-openai) inference engine container";

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/vllm";
      description = "Directory for vLLM model cache and data";
    };

    httpPort = mkOption {
      type = types.port;
      default = 8282;
      description = "Local port for vLLM OpenAI-compatible API";
    };

    model = mkOption {
      type = types.str;
      default = "QuantTrio/Qwen3-VL-30B-A3B-Instruct-AWQ";
      description = "Model identifier from HuggingFace";
    };

    servedModelName = mkOption {
      type = types.str;
      default = "StinkGPT";
      description = "Model name to serve via API";
    };

    gpuMemoryUtilization = mkOption {
      type = types.str;
      default = "0.90";
      description = "The fraction of GPU memory to be used for the model executor";
    };

    maxModelLen = mkOption {
      type = types.int;
      default = 12000;
      description = "Maximum model length";
    };

    maxNumSeqs = mkOption {
      type = types.int;
      default = 8;
      description = "Maximum number of sequences to process at once";
    };

    timezone = mkOption {
      type = types.str;
      default = config.time.timeZone;
      description = "Container timezone";
    };
  };

  config = mkIf cfg.enable {
    # Ensure data directory exists
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
    ];

    virtualisation.oci-containers.containers.vllm = {
      # Disabled by default - start manually with: sudo podman start vllm
      autoStart = false;
      image = "vllm/vllm-openai:latest";
      environment = {
        TZ = cfg.timezone;
      };
      ports = [
        "${toString cfg.httpPort}:8000"
      ];
      volumes = [
        "${cfg.dataDir}:/root/.cache/huggingface"
      ];
      # Using healthy status notification
      podman.sdnotify = "healthy";

      cmd = [
        "--tool-call-parser=hermes"
        "--model=${cfg.model}"
        "--enable-auto-tool-choice"
        "--served-model-name=${cfg.servedModelName}"
        "--gpu-memory-utilization=${cfg.gpuMemoryUtilization}"
        "--max-model-len=${toString cfg.maxModelLen}"
        "--max-num-seqs=${toString cfg.maxNumSeqs}"
      ];

      extraOptions = [
        "--ipc=host"
        "--device=nvidia.com/gpu=all"
        "--health-cmd=curl -f http://127.0.0.1:8000/health"
        "--health-retries=10"
        "--health-interval=30s"
        "--health-start-period=240s"
        "--name=vllm"
      ];
    };

    # Open firewall port
    networking.firewall.allowedTCPPorts = [ cfg.httpPort ];
  };
}
