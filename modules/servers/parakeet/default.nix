##
# Module: servers/parakeet
# Purpose: Parakeet (Wyoming-ONNX-ASR) is a high-performance English ASR engine via Podman.
# Key options: profiles.services.parakeet (enable, dataDir, httpPort, useGpu).
# Dependencies: virtualisation.oci-containers (backend = podman).
{
  lib,
  config,
  ...
}: let
  cfg = config.profiles.services.parakeet;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.profiles.services.parakeet = {
    enable = mkEnableOption "Parakeet (Wyoming-ONNX-ASR) speech-to-text engine container";

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/parakeet";
      description = "Base directory for Parakeet data";
    };

    httpPort = mkOption {
      type = types.port;
      default = 10302;
      description = "Local port for Parakeet service (default: 10302 to avoid conflict with Whisper/Wyoming-OpenAI)";
    };

    useGpu = mkOption {
      type = types.bool;
      default = false;
      description = "Enable NVIDIA GPU acceleration (uses GPU-specific image)";
    };

    timezone = mkOption {
      type = types.str;
      default = "Europe/Moscow";
      description = "Container timezone";
    };
  };

  config = mkIf cfg.enable {
    # Ensure data directory exists
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
      "d ${cfg.dataDir}/data 0755 root root -"
    ];

    virtualisation.oci-containers.containers.parakeet = {
      # Disabled by default - start manually with: sudo podman start parakeet
      autoStart = false;
      image =
        if cfg.useGpu
        then "ghcr.io/tboby/wyoming-onnx-asr-gpu:latest"
        else "ghcr.io/tboby/wyoming-onnx-asr:latest";
      environment = {
        TZ = cfg.timezone;
      };
      ports = [
        "${toString cfg.httpPort}:10300"
      ];
      volumes = [
        "${cfg.dataDir}/data:/data"
      ];
      extraOptions =
        ["--name=parakeet"]
        ++ lib.optional cfg.useGpu "--device=nvidia.com/gpu=all";
    };

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [cfg.httpPort];
  };
}
