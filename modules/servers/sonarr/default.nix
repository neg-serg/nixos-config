##
# Module: servers/sonarr
# Purpose: Sonarr PVR for Usenet and BitTorrent users via Podman.
# Key options: profiles.services.sonarr (enable, dataDir, downloadsDir, tvDir, httpPort).
# Dependencies: virtualisation.oci-containers (backend = podman).
{
  lib,
  config,
  ...
}: let
  cfg = config.profiles.services.sonarr;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.profiles.services.sonarr = {
    enable = mkEnableOption "Sonarr PVR container";

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/sonarr";
      description = "Directory for Sonarr configuration";
    };

    downloadsDir = mkOption {
      type = types.path;
      default = "/storage/downloads";
      description = "Directory for downloads";
    };

    tvDir = mkOption {
      type = types.path;
      default = "/storage/pool/media/watch/tv";
      description = "Directory for TV shows";
    };

    httpPort = mkOption {
      type = types.port;
      default = 8989;
      description = "Port for Sonarr web UI";
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

    virtualisation.oci-containers.containers.sonarr = {
      # Disabled by default - start manually with: sudo podman start sonarr
      autoStart = false;
      image = "lscr.io/linuxserver/sonarr:latest";
      environment = {
        TZ = cfg.timezone;
        PUID = "1000";
        PGID = "100";
      };
      ports = [
        "${toString cfg.httpPort}:8989"
      ];
      volumes = [
        "${cfg.dataDir}:/config"
        "${cfg.downloadsDir}:/downloads"
        "${cfg.tvDir}:/tv"
      ];
      extraOptions = ["--name=sonarr"];
    };

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [cfg.httpPort];
  };
}
