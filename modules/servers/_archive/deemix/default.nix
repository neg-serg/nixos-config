##
# Module: servers/deemix
# Purpose: Deemix is a tool to download music from Deezer via Podman.
# Key options: profiles.services.deemix (enable, dataDir, downloadsDir, httpPort).
# Dependencies: virtualisation.oci-containers (backend = podman).
{
  lib,
  config,
  ...
}:
let
  cfg = config.profiles.services.deemix;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;
in
{
  options.profiles.services.deemix = {
    enable = mkEnableOption "Deemix music downloader container";

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/deemix";
      description = "Directory for Deemix configuration";
    };

    downloadsDir = mkOption {
      type = types.path;
      default = "/storage/downloads/deemix";
      description = "Directory for downloaded music";
    };

    httpPort = mkOption {
      type = types.port;
      default = 6595;
      description = "Port for Deemix web UI";
    };

    timezone = mkOption {
      type = types.str;
      default = config.time.timeZone;
      description = "Container timezone";
    };
  };

  config = mkIf cfg.enable {
    # Ensure data and downloads directories exist
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
      "d ${cfg.downloadsDir} 0755 root root -"
    ];

    virtualisation.oci-containers.containers.deemix = {
      # Disabled by default - start manually with: sudo podman start deemix
      autoStart = false;
      image = "registry.gitlab.com/bockiii/deemix-docker";
      environment = {
        TZ = cfg.timezone;
        PUID = "1000";
        PGID = "100";
        UMASK_SET = "022";
        DEEMIX_SINGLE_USER = "true";
      };
      ports = [
        "${toString cfg.httpPort}:6595"
      ];
      volumes = [
        "${cfg.dataDir}:/config"
        "${cfg.downloadsDir}:/downloads"
      ];
      extraOptions = [ "--name=deemix" ];
    };

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [ cfg.httpPort ];
  };
}
