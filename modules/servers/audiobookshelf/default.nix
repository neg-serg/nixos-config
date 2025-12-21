##
# Module: servers/audiobookshelf
# Purpose: Audiobookshelf is a self-hosted audiobook and podcast server.
# Key options: profiles.services.audiobookshelf (enable, dataDir, listenDir, httpPort).
# Dependencies: virtualisation.oci-containers (backend = podman), services.nginx.
{
  lib,
  config,
  ...
}: let
  cfg = config.profiles.services.audiobookshelf;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.profiles.services.audiobookshelf = {
    enable = mkEnableOption "Audiobookshelf audiobook and podcast server";

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/audiobookshelf";
      description = "Directory for Audiobookshelf configuration and metadata";
    };

    listenDir = mkOption {
      type = types.path;
      default = "/storage/pool/media/listen";
      description = "Directory for audiobooks and podcasts";
    };

    httpPort = mkOption {
      type = types.port;
      default = 1337;
      description = "Local port for Audiobookshelf container";
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
      "d ${cfg.dataDir}/config 0755 root root -"
      "d ${cfg.dataDir}/metadata 0755 root root -"
    ];

    virtualisation.oci-containers.containers.audiobookshelf = {
      # Disabled by default - start manually with: sudo podman start audiobookshelf
      autoStart = false;
      image = "advplyr/audiobookshelf:latest";
      environment = {
        TZ = cfg.timezone;
        PUID = "1000";
        PGID = "100";
      };
      ports = [
        "${toString cfg.httpPort}:80"
      ];
      volumes = [
        "${cfg.dataDir}/config:/config"
        "${cfg.dataDir}/metadata:/metadata"
        "${cfg.listenDir}:/listen"
      ];
      extraOptions = ["--name=audiobookshelf"];
    };

    # Reverse proxy configuration
    services.nginx = {
      enable = true;
      virtualHosts = {
        "listen.stinkboys.com" = {
          serverName = "listen.stinkboys.com";
          forceSSL = true;
          enableACME = true;
          locations."/" = {
            recommendedProxySettings = true;
            proxyWebsockets = true;
            proxyPass = "http://127.0.0.1:${toString cfg.httpPort}";
          };
        };
        "listen.justin-li.me" = {
          serverName = "listen.justin-li.me";
          forceSSL = true;
          enableACME = true;
          locations."/" = {
            recommendedProxySettings = true;
            proxyWebsockets = true;
            proxyPass = "http://127.0.0.1:${toString cfg.httpPort}";
          };
        };
      };
    };

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [cfg.httpPort];
  };
}
