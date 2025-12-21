##
# Module: servers/gitea
# Purpose: Gitea self-hosted Git service container via Podman.
# Key options: profiles.services.gitea (enable, dataDir, httpPort, sshPort, useCaddy, hostName).
# Dependencies: virtualisation.oci-containers (backend = podman), optionally Caddy for HTTPS.
{
  lib,
  config,
  ...
}: let
  cfg = config.profiles.services.gitea;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.profiles.services.gitea = {
    enable = mkEnableOption "Gitea self-hosted Git service container";

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/gitea";
      description = "Directory for Gitea data and repositories";
    };

    httpPort = mkOption {
      type = types.port;
      default = 3000;
      description = "Port for Gitea web UI";
    };

    sshPort = mkOption {
      type = types.port;
      default = 222;
      description = "Port for Gitea SSH access";
    };

    useCaddy = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Caddy reverse proxy with automatic HTTPS";
    };

    hostName = mkOption {
      type = types.str;
      default = "git.localhost";
      description = "Hostname for Caddy virtual host (required if useCaddy = true)";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !(cfg.useCaddy && cfg.hostName == "git.localhost");
        message = "Set profiles.services.gitea.hostName to a real domain when useCaddy = true.";
      }
    ];

    # Ensure data directory exists
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
    ];

    virtualisation.oci-containers.containers.gitea = {
      # Disabled by default - start manually with: sudo podman start gitea
      autoStart = false;
      image = "gitea/gitea:latest";
      environment = {
        USER_UID = "1000";
        USER_GID = "100";
      };
      ports = [
        "${toString cfg.httpPort}:3000"
        "${toString cfg.sshPort}:22"
      ];
      volumes = [
        "${cfg.dataDir}:/data"
        "/etc/localtime:/etc/localtime:ro"
      ];
      extraOptions = ["--name=gitea"];
    };

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [cfg.httpPort cfg.sshPort];

    # Optional: Caddy reverse proxy with automatic HTTPS
    services.caddy = mkIf cfg.useCaddy {
      enable = true;
      virtualHosts.${cfg.hostName}.extraConfig = ''
        encode zstd gzip
        reverse_proxy 127.0.0.1:${toString cfg.httpPort}
      '';
    };
  };
}
