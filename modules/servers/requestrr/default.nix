##
# Module: servers/requestrr
# Purpose: Requestrr is a chatbot used to interact with Sonarr, Radarr, and Ombi.
# Key options: profiles.services.requestrr (enable, dataDir, httpPort).
# Dependencies: virtualisation.oci-containers (backend = podman).
{
  lib,
  config,
  ...
}: let
  cfg = config.profiles.services.requestrr;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.profiles.services.requestrr = {
    enable = mkEnableOption "Requestrr chatbot container";

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/requestrr";
      description = "Directory for Requestrr configuration";
    };

    httpPort = mkOption {
      type = types.port;
      default = 4545;
      description = "Port for Requestrr web UI";
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
    ];

    virtualisation.oci-containers.containers.requestrr = {
      # Disabled by default - start manually with: sudo podman start requestrr
      autoStart = false;
      image = "ghcr.io/hotio/requestrr";
      environment = {
        TZ = cfg.timezone;
        PUID = "1000";
        PGID = "100";
      };
      ports = [
        "${toString cfg.httpPort}:4545"
      ];
      volumes = [
        "${cfg.dataDir}:/config"
      ];
      extraOptions = ["--name=requestrr"];
    };

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [cfg.httpPort];
  };
}
