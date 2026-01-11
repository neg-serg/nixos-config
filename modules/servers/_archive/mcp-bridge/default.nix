##
# Module: servers/mcp-bridge
# Purpose: MCP-Bridge is a bridge between the LLM and various MCP servers via Podman.
# Key options: profiles.services.mcp-bridge (enable, dataDir, httpPort, inferenceServerUrl, searxngUrl, qdrantHost, qdrantPort).
# Dependencies: virtualisation.oci-containers (backend = podman).
{
  lib,
  config,
  ...
}:
let
  cfg = config.profiles.services.mcp-bridge;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;

  mcpConfig = {
    inference_server = {
      base_url = cfg.inferenceServerUrl;
      api_key = "None";
    };
    mcp_servers = {
      searxng = {
        command = "npx";
        args = [
          "-y"
          "mcp-searxng"
        ];
        env = {
          SEARXNG_URL = cfg.searxngUrl;
        };
      };
      easy_mcp_rag = {
        command = "uvx";
        args = [
          "--from"
          "git+https://github.com/justinlime/easy_mcp_rag.git"
          "easy_mcp_rag"
          "--qdrant-host"
          cfg.qdrantHost
          "--qdrant-port"
          (toString cfg.qdrantPort)
          "--data-dir"
          "/docs"
        ];
      };
    };
  };
in
{
  options.profiles.services.mcp-bridge = {
    enable = mkEnableOption "MCP-Bridge gateway container";

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/mcp-bridge";
      description = "Base directory for MCP-Bridge persistent data";
    };

    httpPort = mkOption {
      type = types.port;
      default = 9420;
      description = "Local port for MCP-Bridge service";
    };

    inferenceServerUrl = mkOption {
      type = types.str;
      default = "http://10.69.42.200:8282/v1";
      description = "Base URL for the inference server (vLLM)";
    };

    searxngUrl = mkOption {
      type = types.str;
      default = "http://10.69.42.200:8181";
      description = "URL for the SearXNG search engine";
    };

    qdrantHost = mkOption {
      type = types.str;
      default = "10.69.42.200";
      description = "Host for the Qdrant vector database";
    };

    qdrantPort = mkOption {
      type = types.port;
      default = 6333;
      description = "Port for the Qdrant vector database";
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
      "d ${cfg.dataDir}/uv 0755 root root -"
      "d ${cfg.dataDir}/npm 0755 root root -"
      "d ${cfg.dataDir}/docs 0755 root root -"
    ];

    virtualisation.oci-containers.containers.mcp-bridge = {
      # Disabled by default - start manually with: sudo podman start mcp-bridge
      autoStart = false;
      image = "justinlime/mcp-bridge:latest";
      environment = {
        TZ = cfg.timezone;
        MCP_BRIDGE__CONFIG__JSON = builtins.toJSON mcpConfig;
      };
      ports = [
        "${toString cfg.httpPort}:8000"
      ];
      volumes = [
        "${cfg.dataDir}/uv:/root/.cache/uv"
        "${cfg.dataDir}/npm:/root/.npm"
        "${cfg.dataDir}/docs:/docs"
      ];
      extraOptions = [ "--name=mcp-bridge" ];
    };

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [ cfg.httpPort ];
  };
}
