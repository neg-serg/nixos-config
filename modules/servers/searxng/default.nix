##
# Module: servers/searxng
# Purpose: SearXNG privacy-respecting metasearch engine container via Podman.
# Key options: profiles.services.searxng (enable, dataDir, httpPort).
# Dependencies: virtualisation.oci-containers (backend = podman).
{
  lib,
  config,
  ...
}: let
  cfg = config.profiles.services.searxng;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.profiles.services.searxng = {
    enable = mkEnableOption "SearXNG metasearch engine container";

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/searxng";
      description = "Directory for SearXNG configuration and cache";
    };

    httpPort = mkOption {
      type = types.port;
      default = 8181;
      description = "Port for SearXNG web UI";
    };
  };

  config = mkIf cfg.enable {
    # Ensure data directories exist
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir}/data 0755 root root -"
      "d ${cfg.dataDir}/config 0755 root root -"
    ];

    virtualisation.oci-containers.containers.searxng = {
      # Disabled by default - start manually with: sudo podman start searxng
      autoStart = false;
      image = "docker.io/searxng/searxng:latest";
      ports = ["${toString cfg.httpPort}:8080"];
      volumes = [
        "${cfg.dataDir}/data:/var/cache/searxng"
        "${cfg.dataDir}/config:/etc/searxng"
      ];
      extraOptions = ["--name=searxng"];
    };

    # Open firewall port for web UI
    networking.firewall.allowedTCPPorts = [cfg.httpPort];
  };
}
