##
# Module: servers/prowlarr
# Purpose: Prowlarr is an indexer manager/proxy (for Sonarr/Radarr) via Podman.
# Key options: profiles.services.prowlarr (enable, dataDir, httpPort).
# Dependencies: virtualisation.oci-containers (backend = podman).
{
  lib,
  config,
  ...
}: let
  cfg = config.profiles.services.prowlarr;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.profiles.services.prowlarr = {
    enable = mkEnableOption "Prowlarr indexer manager container";

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/prowlarr";
      description = "Directory for Prowlarr configuration";
    };

    httpPort = mkOption {
      type = types.port;
      default = 9696;
      description = "Port for Prowlarr web UI";
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
    ];

    virtualisation.oci-containers.containers.prowlarr = {
      # Disabled by default - start manually with: sudo podman start prowlarr
      autoStart = false;
      image = "lscr.io/linuxserver/prowlarr:latest";
      environment = {
        TZ = cfg.timezone;
        PUID = "1000";
        PGID = "100";
      };
      ports = [
        "${toString cfg.httpPort}:9696"
      ];
      volumes = [
        "${cfg.dataDir}:/config"
      ];
      extraOptions = ["--name=prowlarr"];
    };

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [cfg.httpPort];
  };
}
