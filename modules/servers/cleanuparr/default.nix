##
# Module: servers/cleanuparr
# Purpose: Cleanuparr is a tool to clean up your *arr instance via Podman.
# Key options: profiles.services.cleanuparr (enable, dataDir, httpPort).
# Dependencies: virtualisation.oci-containers (backend = podman).
{
  lib,
  config,
  ...
}: let
  cfg = config.profiles.services.cleanuparr;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.profiles.services.cleanuparr = {
    enable = mkEnableOption "Cleanuparr maintenance tool container";

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/cleanuparr";
      description = "Directory for Cleanuparr configuration";
    };

    httpPort = mkOption {
      type = types.port;
      default = 11011;
      description = "Port for Cleanuparr web UI";
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

    virtualisation.oci-containers.containers.cleanuparr = {
      # Disabled by default - start manually with: sudo podman start cleanuparr
      autoStart = false;
      image = "ghcr.io/cleanuparr/cleanuparr:latest";
      environment = {
        TZ = cfg.timezone;
        PUID = "1000";
        PGID = "100";
      };
      ports = [
        "${toString cfg.httpPort}:11011"
      ];
      volumes = [
        "${cfg.dataDir}:/config"
      ];
      extraOptions = ["--name=cleanuparr"];
    };

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [cfg.httpPort];
  };
}
