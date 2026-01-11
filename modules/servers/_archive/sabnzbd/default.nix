##
# Module: servers/sabnzbd
# Purpose: SABnzbd Usenet downloader container via Podman.
# Key options: profiles.services.sabnzbd (enable, dataDir, downloadsDir, httpPort, timezone).
# Dependencies: virtualisation.oci-containers (backend = podman).
{
  lib,
  config,
  ...
}:
let
  cfg = config.profiles.services.sabnzbd;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;
in
{
  options.profiles.services.sabnzbd = {
    enable = mkEnableOption "SABnzbd Usenet downloader container";

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/sabnzbd";
      description = "Directory for SABnzbd configuration";
    };

    downloadsDir = mkOption {
      type = types.path;
      default = "/var/lib/sabnzbd/downloads";
      description = "Directory for downloads";
    };

    httpPort = mkOption {
      type = types.port;
      default = 8081;
      description = "Port for SABnzbd web UI";
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
      "d ${cfg.downloadsDir} 0755 root root -"
    ];

    virtualisation.oci-containers.containers.sabnzbd = {
      # Disabled by default - start manually with: sudo podman start sabnzbd
      autoStart = false;
      image = "lscr.io/linuxserver/sabnzbd:latest";
      environment = {
        TZ = cfg.timezone;
        PUID = "1000";
        PGID = "100";
      };
      ports = [ "${toString cfg.httpPort}:8080" ];
      volumes = [
        "${cfg.dataDir}:/config"
        "${cfg.downloadsDir}:/downloads"
      ];
      extraOptions = [ "--name=sabnzbd" ];
    };

    # Open firewall port for web UI
    networking.firewall.allowedTCPPorts = [ cfg.httpPort ];
  };
}
