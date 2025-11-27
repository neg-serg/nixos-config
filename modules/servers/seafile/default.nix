##
# Module: servers/seafile
# Purpose: Seafile server profile implemented via Podman (oci-containers) and optional Caddy reverse proxy.
# Key options: cfg = config.servicesProfiles.seafile (enable, hostName, dataDir, adminEmail, adminPassword, dbRootPassword, httpPort, useCaddy).
# Dependencies: virtualisation.oci-containers (backend = podman), Caddy for HTTPS termination.
{
  lib,
  config,
  ...
}: let
  cfg =
    config.servicesProfiles.seafile or {
      enable = false;
      hostName = "localhost";
      dataDir = "/seafile";
      adminEmail = "admin@example.com";
      adminPassword = "change-me";
      dbRootPassword = "change-me";
      httpPort = 8082;
      useCaddy = true;
    };
  hostName = cfg.hostName;
  httpPort = cfg.httpPort;
in {
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(cfg.useCaddy && hostName == "localhost");
        message = "Set servicesProfiles.seafile.hostName to a public or LAN DNS name when useCaddy = true.";
      }
    ];

    # Database and cache for Seafile
    virtualisation.oci-containers.containers = {
      "seafile-db" = {
        image = "mariadb:10.11";
        autoStart = true;
        volumes = ["${cfg.dataDir}/db:/var/lib/mysql"];
        environment = {
          MYSQL_ROOT_PASSWORD = cfg.dbRootPassword;
          MYSQL_LOG_CONSOLE = "true";
        };
      };

      "seafile-memcached" = {
        image = "memcached:1.6";
        autoStart = true;
        cmd = ["memcached" "-m" "256"];
      };

      "seafile" = {
        # Official multi-component Seafile server image
        image = "docker.seafile.top/seafileltd/seafile-mc:11.0-latest";
        autoStart = true;
        ports = ["127.0.0.1:${toString httpPort}:80"];
        volumes = ["${cfg.dataDir}/seafile:/shared"];
        environment = {
          DB_HOST = "seafile-db";
          DB_ROOT_PASSWD = cfg.dbRootPassword;
          SEAFILE_ADMIN_EMAIL = cfg.adminEmail;
          SEAFILE_ADMIN_PASSWORD = cfg.adminPassword;
          SEAFILE_SERVER_HOSTNAME = hostName;
          SEAFILE_SERVER_LETSENCRYPT =
            if cfg.useCaddy
            then "false"
            else "true";
        };
      };
    };

    # Optional: Caddy reverse proxy with automatic HTTPS
    networking.firewall = lib.mkIf cfg.useCaddy {
      allowedTCPPorts = [80 443];
    };

    services.caddy = lib.mkIf cfg.useCaddy {
      enable = true;
      email = lib.mkDefault "change-me@example.com";
      virtualHosts.${hostName}.extraConfig = ''
        encode zstd gzip
        reverse_proxy 127.0.0.1:${toString httpPort}
      '';
    };
  };
}
