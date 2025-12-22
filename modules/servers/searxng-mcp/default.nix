##
# Module: servers/searxng-mcp
# Purpose: MCP (Model Context Protocol) server for SearXNG.
# Key options: profiles.services.searxng-mcp (enable, searxngUrl, httpPort).
# Dependencies: virtualisation.oci-containers (backend = podman).
{
  lib,
  config,
  ...
}: let
  cfg = config.profiles.services.searxng-mcp;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.profiles.services.searxng-mcp = {
    enable = mkEnableOption "SearXNG-MCP bridge container";

    searxngUrl = mkOption {
      type = types.str;
      default = "http://10.69.42.200:8181";
      description = "URL of the SearXNG instance to connect to";
    };

    httpPort = mkOption {
      type = types.port;
      default = 9191;
      description = "Local port for SearXNG-MCP service";
    };

    timezone = mkOption {
      type = types.str;
      default = "Europe/Moscow";
      description = "Container timezone";
    };
  };

  config = mkIf cfg.enable {
    virtualisation.oci-containers.containers.searxng-mcp = {
      # Disabled by default - start manually with: sudo podman start searxng-mcp
      autoStart = false;
      image = "isokoliuk/mcp-searxng:latest";
      environment = {
        SEARXNG_URL = cfg.searxngUrl;
        MCP_HTTP_PORT = "8080";
        TZ = cfg.timezone;
      };
      ports = [
        "${toString cfg.httpPort}:8080"
      ];
      extraOptions = ["--name=searxng-mcp"];
    };

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [cfg.httpPort];
  };
}
