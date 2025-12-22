##
# Module: servers/komga
# Purpose: Komga is a free and open source comics/mangas media server.
# Key options: profiles.services.komga (enable, dataDir, readDir, httpPort).
# Dependencies: virtualisation.oci-containers (backend = podman).
{
  lib,
  config,
  ...
}: let
  cfg = config.profiles.services.komga;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.profiles.services.komga = {
    enable = mkEnableOption "Komga comics/mangas media server container";

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/komga";
      description = "Directory for Komga configuration and data";
    };

    readDir = mkOption {
      type = types.path;
      default = "/storage/pool/media/read";
      description = "Directory for media (comics/mangas) to read";
    };

    httpPort = mkOption {
      type = types.port;
      default = 25600;
      description = "Port for Komga web UI";
    };

    timezone = mkOption {
      type = types.str;
      default = config.time.timeZone;
      description = "Container timezone";
    };
  };

  config = mkIf cfg.enable {
    # Ensure data directory and subdirs exist
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
      "d ${cfg.dataDir}/config 0755 root root -"
      "d ${cfg.dataDir}/data 0755 root root -"
    ];

    virtualisation.oci-containers.containers.komga = {
      # Disabled by default - start manually with: sudo podman start komga
      autoStart = false;
      image = "gotson/komga:latest";
      environment = {
        TZ = cfg.timezone;
      };
      ports = [
        "${toString cfg.httpPort}:25600"
      ];
      volumes = [
        "${cfg.dataDir}/config:/config"
        "${cfg.dataDir}/data:/data"
        "${cfg.readDir}:/read"
        "/etc/localtime:/etc/localtime:ro"
      ];
      extraOptions = ["--name=komga"];
    };

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [cfg.httpPort];
  };
}
