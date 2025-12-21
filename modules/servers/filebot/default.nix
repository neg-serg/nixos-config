##
# Module: servers/filebot
# Purpose: FileBot is the ultimate tool for organizing and renaming your movies, TV shows and anime.
# Key options: profiles.services.filebot (enable, dataDir, storageDir, httpPort).
# Dependencies: virtualisation.oci-containers (backend = podman).
{
  lib,
  config,
  ...
}: let
  cfg = config.profiles.services.filebot;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.profiles.services.filebot = {
    enable = mkEnableOption "FileBot organizer container";

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/filebot";
      description = "Directory for FileBot configuration";
    };

    storageDir = mkOption {
      type = types.path;
      default = "/storage/pool";
      description = "Directory for media storage to organize";
    };

    httpPort = mkOption {
      type = types.port;
      default = 5800;
      description = "Port for FileBot web UI";
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

    virtualisation.oci-containers.containers.filebot = {
      # Disabled by default - start manually with: sudo podman start filebot
      autoStart = false;
      image = "jlesage/filebot";
      environment = {
        TZ = cfg.timezone;
        PUID = "1000";
        PGID = "100";
      };
      ports = [
        "${toString cfg.httpPort}:5800"
      ];
      volumes = [
        "${cfg.dataDir}:/config"
        "${cfg.storageDir}:/storage"
      ];
      extraOptions = ["--name=filebot"];
    };

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [cfg.httpPort];
  };
}
