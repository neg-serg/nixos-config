##
# Module: servers/syncthing
# Purpose: Syncthing container profile implemented via Podman (oci-containers).
# Key options: profiles.services.syncthing (enable, dataDir, syncDirs, httpPort, timezone).
# Dependencies: virtualisation.oci-containers (backend = podman).
{
  lib,
  config,
  ...
}: let
  cfg = config.profiles.services.syncthing;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.profiles.services.syncthing = {
    enable = mkEnableOption "Syncthing file synchronization container";

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/syncthing";
      description = "Directory for Syncthing configuration and database";
    };

    syncDirs = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["/home/user/Documents:/documents" "/home/user/Photos:/photos"];
      description = "List of volume mounts in format 'host_path:container_path'";
    };

    httpPort = mkOption {
      type = types.port;
      default = 8384;
      description = "Port for Syncthing web UI";
    };

    timezone = mkOption {
      type = types.str;
      default = "Europe/Moscow";
      description = "Container timezone";
    };

    hostname = mkOption {
      type = types.str;
      default = config.networking.hostName;
      description = "Container hostname";
    };
  };

  config = mkIf cfg.enable {
    # Ensure data directory exists
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
    ];

    virtualisation.oci-containers.containers.syncthing = {
      # Disabled by default - start manually with: sudo podman start syncthing
      autoStart = false;
      image = "lscr.io/linuxserver/syncthing:latest";
      environment = {
        TZ = cfg.timezone;
        PUID = "1000";
        PGID = "100";
      };
      ports = [
        "${toString cfg.httpPort}:8384" # Web UI
        "22000:22000/tcp" # TCP file transfers
        "22000:22000/udp" # QUIC file transfers
        "21027:21027/udp" # Discovery broadcasts
      ];
      volumes = ["${cfg.dataDir}:/config"] ++ cfg.syncDirs;
      extraOptions = [
        "--hostname=${cfg.hostname}-syncthing"
        "--name=syncthing"
      ];
    };

    # Open firewall ports for Syncthing discovery and transfer
    networking.firewall = {
      allowedTCPPorts = [cfg.httpPort 22000];
      allowedUDPPorts = [22000 21027];
    };
  };
}
