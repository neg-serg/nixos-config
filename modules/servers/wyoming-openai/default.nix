##
# Module: servers/wyoming-openai
# Purpose: Wyoming OpenAI proxy — bridges Wyoming protocol with OpenAI-compatible STT/TTS endpoints.
# Key options: cfg = config.servicesProfiles.wyoming-openai (enable, stt.*, tts.*)
# Dependencies: pkgs.neg.wyoming-openai
#
# API keys are passed via environment variables (more secure than CLI args).
# All other options use CLI arguments.
{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.servicesProfiles.wyoming-openai or { enable = false; };
  opts = import (inputs.self + "/lib/opts.nix") { inherit lib; };
  inherit (lib) types;
  ep = lib.escapeShellArg;

  # Build CLI args for an endpoint (stt or tts)
  mkEndpointArgs =
    prefix: epCfg:
    lib.optionals epCfg.enable (
      (lib.optional (epCfg ? "url") "--${prefix}-openai-url ${ep epCfg.url}")
      ++ (lib.optional (epCfg ? "models" && epCfg.models != [ ]) "--${prefix}-models ${lib.concatStringsSep " " (map ep epCfg.models)}")
      ++ (lib.optional (epCfg ? "streamingModels" && epCfg.streamingModels != [ ]) "--${prefix}-streaming-models ${lib.concatStringsSep " " (map ep epCfg.streamingModels)}")
      ++ (lib.optional (epCfg ? "backend") "--${prefix}-backend ${ep epCfg.backend}")
      ++ (lib.optional (epCfg ? "temperature") "--${prefix}-temperature ${toString epCfg.temperature}")
      ++ (lib.optional (epCfg ? "prompt") "--${prefix}-prompt ${ep epCfg.prompt}")
    );

  ttsArgs = lib.optionals cfg.tts.enable (
    (lib.optional (cfg.tts ? "voices" && cfg.tts.voices != [ ]) "--tts-voices ${lib.concatStringsSep " " (map ep cfg.tts.voices)}")
    ++ (lib.optional (cfg.tts ? "speed") "--tts-speed ${toString cfg.tts.speed}")
    ++ (lib.optional (cfg.tts ? "instructions") "--tts-instructions ${ep cfg.tts.instructions}")
    ++ (lib.optional (cfg.tts ? "streamingMinWords") "--tts-streaming-min-words ${toString cfg.tts.streamingMinWords}")
    ++ (lib.optional (cfg.tts ? "streamingMaxChars") "--tts-streaming-max-chars ${toString cfg.tts.streamingMaxChars}")
  );

  cliArgs = lib.concatStringsSep " " (
    [ "--uri ${ep cfg.uri}" ]
    ++ lib.optional (cfg.logLevel != "") "--log-level ${ep cfg.logLevel}"
    ++ lib.optional (cfg.languages != [ ]) "--languages ${lib.concatStringsSep " " (map ep cfg.languages)}"
    ++ mkEndpointArgs "stt" cfg.stt
    ++ mkEndpointArgs "tts" cfg.tts
    ++ ttsArgs
  );

  # Environment variables for API keys (read by upstream's CLI parser)
  envVars =
    { }
    // lib.optionalAttrs (cfg.stt.enable && cfg.stt ? "key") { STT_OPENAI_KEY = cfg.stt.key; }
    // lib.optionalAttrs (cfg.tts.enable && cfg.tts ? "key") { TTS_OPENAI_KEY = cfg.tts.key; };
in
{
  imports = [ ];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.stt.enable || cfg.tts.enable;
        message = "Wyoming OpenAI requires at least one of stt.enable or tts.enable.";
      }
    ];

    environment.systemPackages = [ pkgs.neg.wyoming-openai ];

    systemd.services.wyoming-openai = {
      description = "Wyoming OpenAI Proxy — STT/TTS bridge for Home Assistant";
      documentation = [ "https://github.com/roryeckel/wyoming-openai" ];
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      wants = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${lib.getExe pkgs.neg.wyoming-openai} ${cliArgs}";
        Restart = "on-failure";
        RestartSec = "5s";
        DynamicUser = true;
        StateDirectory = "wyoming-openai";
        StateDirectoryMode = "0750";
        # Hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        CapabilityBoundingSet = "";
      };

      inherit envVars;
    };
  };
}
