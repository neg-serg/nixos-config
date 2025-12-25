##
# Module: servers/wyoming-openai
# Purpose: Wyoming protocol bridge for OpenAI-compatible TTS services.
# Key options: profiles.services.wyoming-openai (enable, openaiUrl, httpPort).
# Dependencies: virtualisation.oci-containers (backend = podman).
{
  lib,
  config,
  ...
}: let
  cfg = config.profiles.services.wyoming-openai;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.profiles.services.wyoming-openai = {
    enable = mkEnableOption "Wyoming-OpenAI bridge container";

    openaiUrl = mkOption {
      type = types.str;
      default = "http://10.69.42.200:1314/v1";
      description = "URL of the OpenAI-compatible API";
    };

    httpPort = mkOption {
      type = types.port;
      default = 10301;
      description = "Local port for Wyoming-OpenAI service";
    };

    ttsModels = mkOption {
      type = types.str;
      default = "tts-1";
      description = "TTS models to use";
    };

    ttsStreamingModels = mkOption {
      type = types.str;
      default = "tts-1";
      description = "TTS streaming models to use";
    };

    ttsBackend = mkOption {
      type = types.str;
      default = "OPENAI";
      description = "TTS backend to use";
    };

    ttsVoices = mkOption {
      type = types.str;
      default = "alloy";
      description = "TTS voices to use";
    };

    ttsSpeed = mkOption {
      type = types.str;
      default = "1.0";
      description = "TTS playback speed";
    };

    logLevel = mkOption {
      type = types.str;
      default = "DEBUG";
      description = "Logging level";
    };

    timezone = mkOption {
      type = types.str;
      default = config.time.timeZone;
      description = "Container timezone";
    };
  };

  config = mkIf cfg.enable {
    virtualisation.oci-containers.containers.wyoming-openai = {
      # Disabled by default - start manually with: sudo podman start wyoming-openai
      autoStart = false;
      image = "ghcr.io/roryeckel/wyoming_openai:latest";
      environment = {
        TZ = cfg.timezone;
        LOG_LEVEL = cfg.logLevel;
        TTS_OPENAI_URL = cfg.openaiUrl;
        TTS_MODELS = cfg.ttsModels;
        TTS_STREAMING_MODELS = cfg.ttsStreamingModels;
        TTS_BACKEND = cfg.ttsBackend;
        TTS_VOICES = cfg.ttsVoices;
        TTS_SPEED = cfg.ttsSpeed;
        WYOMING_URI = "tcp://0.0.0.0:10300";
      };
      ports = [
        "${toString cfg.httpPort}:10300"
      ];
      extraOptions = ["--name=wyoming-openai"];
    };

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [cfg.httpPort];
  };
}
