##
# Module: servers/plex
# Purpose: Plex Media Server via Podman.
# Key options: profiles.services.plex (enable, dataDir, moviesDir, tvDir, animeDir).
# Dependencies: virtualisation.oci-containers (backend = podman).
{
  lib,
  config,
  ...
}: let
  cfg = config.profiles.services.plex;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.profiles.services.plex = {
    enable = mkEnableOption "Plex Media Server container";

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/plex";
      description = "Directory for Plex configuration";
    };

    moviesDir = mkOption {
      type = types.path;
      default = "/storage/pool/media/watch/movies";
      description = "Directory for movies";
    };

    tvDir = mkOption {
      type = types.path;
      default = "/storage/pool/media/watch/tv";
      description = "Directory for TV shows";
    };

    animeDir = mkOption {
      type = types.path;
      default = "/storage/pool/media/watch/anime";
      description = "Directory for anime";
    };

    timezone = mkOption {
      type = types.str;
      default = config.time.timeZone;
      description = "Container timezone";
    };

    enableGpu = mkOption {
      type = types.bool;
      default = true;
      description = "Enable GPU acceleration (/dev/dri)";
    };
  };

  config = mkIf cfg.enable {
    # Ensure data directory exists
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
    ];

    virtualisation.oci-containers.containers.plex = {
      # Disabled by default - start manually with: sudo podman start plex
      autoStart = false;
      image = "lscr.io/linuxserver/plex:latest";
      environment = {
        TZ = cfg.timezone;
        PUID = "1000";
        PGID = "100";
      };
      ports = [
        "32400:32400"
      ];
      volumes = [
        "${cfg.dataDir}:/config"
        "${cfg.moviesDir}:/movies"
        "${cfg.tvDir}:/tv"
        "${cfg.animeDir}:/anime"
      ];
      extraOptions =
        ["--name=plex"]
        ++ (lib.optional cfg.enableGpu "--device=/dev/dri:/dev/dri");
    };

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [32400];
  };
}
