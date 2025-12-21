##
# Module: servers/huntarr
# Purpose: Huntarr is a search aggregator for the *arr suite via Podman.
# Key options: profiles.services.huntarr (enable, dataDir, httpPort).
# Dependencies: virtualisation.oci-containers (backend = podman).
{
  lib,
  config,
  ...
}: let
  cfg = config.profiles.services.huntarr;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.profiles.services.huntarr = {
    enable = mkEnableOption "Huntarr search aggregator container";

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/huntarr";
      description = "Directory for Huntarr configuration";
    };

    httpPort = mkOption {
      type = types.port;
      default = 9705;
      description = "Port for Huntarr web UI";
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

    virtualisation.oci-containers.containers.huntarr = {
      # Disabled by default - start manually with: sudo podman start huntarr
      autoStart = false;
      image = "ghcr.io/plexguide/huntarr:latest";
      environment = {
        TZ = cfg.timezone;
        PUID = "1000";
        PGID = "100";
      };
      ports = [
        "${toString cfg.httpPort}:9705"
      ];
      volumes = [
        "${cfg.dataDir}:/config"
      ];
      extraOptions = ["--name=huntarr"];
    };

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [cfg.httpPort];
  };
}
