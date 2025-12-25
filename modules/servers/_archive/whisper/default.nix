##
# Module: servers/whisper
# Purpose: Faster-Whisper is a high-performance speech-to-text engine via Podman.
# Key options: profiles.services.whisper (enable, model, language, httpPort, useGpu, dataDir).
# Dependencies: virtualisation.oci-containers (backend = podman).
{
  lib,
  config,
  ...
}: let
  cfg = config.profiles.services.whisper;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.profiles.services.whisper = {
    enable = mkEnableOption "Faster-Whisper speech-to-text engine container";

    model = mkOption {
      type = types.str;
      default = "large-v3-turbo";
      description = "Whisper model to use (e.g., base, medium, large-v3-turbo)";
    };

    language = mkOption {
      type = types.str;
      default = "en";
      description = "Transcription language (e.g., en, ru)";
    };

    httpPort = mkOption {
      type = types.port;
      default = 10300;
      description = "Local port for Whisper service";
    };

    useGpu = mkOption {
      type = types.bool;
      default = true;
      description = "Enable NVIDIA GPU acceleration";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/whisper";
      description = "Directory for Whisper configuration and models";
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
      "d ${cfg.dataDir}/config 0755 root root -"
    ];

    virtualisation.oci-containers.containers.whisper = {
      # Disabled by default - start manually with: sudo podman start whisper
      autoStart = false;
      image = "lscr.io/linuxserver/faster-whisper:gpu";
      environment = {
        PUID = "1000";
        PGID = "100";
        TZ = cfg.timezone;
        WHISPER_MODEL = cfg.model;
        WHISPER_LANG = cfg.language;
      };
      ports = [
        "${toString cfg.httpPort}:10300"
      ];
      volumes = [
        "${cfg.dataDir}/config:/config"
      ];
      extraOptions =
        ["--name=whisper"]
        ++ lib.optional cfg.useGpu "--device=nvidia.com/gpu=all";
    };

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [cfg.httpPort];
  };
}
