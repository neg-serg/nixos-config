##
# Module: servers/open-webui
# Purpose: Open WebUI is a user-friendly WebUI for LLMs via Podman.
# Key options: profiles.services.open-webui (enable, dataDir, httpPort, openaiApiUrl, vectorDb, qdrantUri).
# Dependencies: virtualisation.oci-containers (backend = podman), Nginx.
{
  lib,
  config,
  ...
}: let
  cfg = config.profiles.services.open-webui;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.profiles.services.open-webui = {
    enable = mkEnableOption "Open WebUI container";

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/open-webui";
      description = "Directory for Open WebUI data";
    };

    httpPort = mkOption {
      type = types.port;
      default = 4242;
      description = "Local port for Open WebUI";
    };

    openaiApiUrl = mkOption {
      type = types.str;
      default = "http://10.69.42.200:8282/v1";
      description = "Base URL for OpenAI-compatible API";
    };

    vectorDb = mkOption {
      type = types.str;
      default = "qdrant";
      description = "Vector database type (e.g., qdrant, chromadb)";
    };

    qdrantUri = mkOption {
      type = types.str;
      default = "http://10.69.42.200:6333";
      description = "URI for Qdrant database";
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

    virtualisation.oci-containers.containers.open-webui = {
      # Disabled by default - start manually with: sudo podman start open-webui
      autoStart = false;
      image = "ghcr.io/open-webui/open-webui:main";
      environment = {
        TZ = cfg.timezone;
        OPENAI_API_BASE_URL = cfg.openaiApiUrl;
        USE_OLLAMA = "false";
        VECTOR_DB = cfg.vectorDb;
        QDRANT_URI = cfg.qdrantUri;
      };
      ports = [
        "${toString cfg.httpPort}:8080"
      ];
      volumes = [
        "${cfg.dataDir}/data:/app/backend/data"
      ];
      extraOptions = ["--name=open-webui"];
    };

    # Open firewall port
    networking.firewall.allowedTCPPorts = [cfg.httpPort];

    # Nginx reverse proxy
    services.nginx = {
      enable = true;
      virtualHosts = {
        "ai.justin-li.me" = {
          forceSSL = true;
          enableACME = true;
          locations."/" = {
            recommendedProxySettings = true;
            proxyWebsockets = true;
            proxyPass = "http://127.0.0.1:${toString cfg.httpPort}";
          };
        };
        "chat.justin-li.me" = {
          forceSSL = true;
          enableACME = true;
          locations."/" = {
            recommendedProxySettings = true;
            proxyWebsockets = true;
            proxyPass = "http://127.0.0.1:${toString cfg.httpPort}";
          };
        };
      };
    };
  };
}
