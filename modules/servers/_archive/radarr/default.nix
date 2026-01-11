##
# Module: servers/radarr
# Purpose: Radarr movie PVR for Usenet and BitTorrent users via Podman.
# Key options: profiles.services.radarr (enable, dataDir, downloadsDir, moviesDir, httpPort).
# Dependencies: virtualisation.oci-containers (backend = podman).
{
  lib,
  config,
  ...
}:
let
  cfg = config.profiles.services.radarr;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;
in
{
  options.profiles.services.radarr = {
    enable = mkEnableOption "Radarr movie PVR container";

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/radarr";
      description = "Directory for Radarr configuration";
    };

    downloadsDir = mkOption {
      type = types.path;
      default = "/storage/downloads";
      description = "Directory for downloads";
    };

    moviesDir = mkOption {
      type = types.path;
      default = "/storage/pool/media/watch/movies";
      description = "Directory for movies";
    };

    httpPort = mkOption {
      type = types.port;
      default = 7878;
      description = "Port for Radarr web UI";
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

    virtualisation.oci-containers.containers.radarr = {
      # Disabled by default - start manually with: sudo podman start radarr
      autoStart = false;
      image = "lscr.io/linuxserver/radarr:latest";
      environment = {
        TZ = cfg.timezone;
        PUID = "1000";
        PGID = "100";
      };
      ports = [
        "${toString cfg.httpPort}:7878"
      ];
      volumes = [
        "${cfg.dataDir}:/config"
        "${cfg.downloadsDir}:/downloads"
        "${cfg.moviesDir}:/movies"
      ];
      extraOptions = [ "--name=radarr" ];
    };

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [ cfg.httpPort ];
  };
}
