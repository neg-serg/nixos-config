##
# Module: servers/tts-webui
# Purpose: TTS-WebUI is a web interface for various TTS engines via Podman.
# Key options: profiles.services.tts-webui (enable, dataDir, httpPort, uiPort, extraPort, useGpu).
# Dependencies: virtualisation.oci-containers (backend = podman).
{
  lib,
  config,
  ...
}: let
  cfg = config.profiles.services.tts-webui;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.profiles.services.tts-webui = {
    enable = mkEnableOption "TTS-WebUI container";

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/tts-webui";
      description = "Base directory for TTS-WebUI data";
    };

    httpPort = mkOption {
      type = types.port;
      default = 7770;
      description = "Main port for TTS-WebUI";
    };

    uiPort = mkOption {
      type = types.port;
      default = 3330;
      description = "UI port for TTS-WebUI (maps to internal 3000)";
    };

    extraPort = mkOption {
      type = types.port;
      default = 7778;
      description = "Extra service port for TTS-WebUI";
    };

    useGpu = mkOption {
      type = types.bool;
      default = true;
      description = "Enable NVIDIA GPU acceleration";
    };

    timezone = mkOption {
      type = types.str;
      default = config.time.timeZone;
      description = "Container timezone";
    };
  };

  config = mkIf cfg.enable {
    # Ensure data directories exist
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
      "d ${cfg.dataDir}/data 0755 root root -"
      "d ${cfg.dataDir}/outputs 0755 root root -"
      "d ${cfg.dataDir}/favorites 0755 root root -"
    ];

    virtualisation.oci-containers.containers.tts-webui = {
      # Disabled by default - start manually with: sudo podman start tts-webui
      autoStart = false;
      image = "ghcr.io/rsxdalv/tts-webui:main";
      environment = {
        TZ = cfg.timezone;
      };
      ports = [
        "${toString cfg.httpPort}:7770"
        "${toString cfg.uiPort}:3000"
        "${toString cfg.extraPort}:7778"
      ];
      volumes = [
        "${cfg.dataDir}/data:/app/tts-webui/data"
        "${cfg.dataDir}/outputs:/app/tts-webui/outputs"
        "${cfg.dataDir}/favorites:/app/tts-webui/favorites"
      ];
      extraOptions =
        ["--name=tts-webui"]
        ++ lib.optional cfg.useGpu "--device=nvidia.com/gpu=all";
    };

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [cfg.httpPort cfg.uiPort cfg.extraPort];
  };
}
