##
# Module: servers/portainer
# Purpose: Portainer container management UI via Podman.
# Key options: profiles.services.portainer (enable, dataDir, httpPort, httpsPort).
# Dependencies: virtualisation.oci-containers (backend = podman).
{
  lib,
  config,
  ...
}:
let
  cfg = config.profiles.services.portainer;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;
in
{
  options.profiles.services.portainer = {
    enable = mkEnableOption "Portainer container management UI";

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/portainer";
      description = "Directory for Portainer data";
    };

    httpPort = mkOption {
      type = types.port;
      default = 9000;
      description = "Port for Portainer HTTP web UI";
    };

    httpsPort = mkOption {
      type = types.port;
      default = 9443;
      description = "Port for Portainer HTTPS web UI";
    };

    edgePort = mkOption {
      type = types.port;
      default = 8000;
      description = "Port for Portainer Edge Agent communication";
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

    virtualisation.oci-containers.containers.portainer = {
      # Disabled by default - start manually with: sudo podman start portainer
      autoStart = false;
      image = "portainer/portainer-ce:latest";
      environment = {
        TZ = cfg.timezone;
      };
      ports = [
        "${toString cfg.httpPort}:9000"
        "${toString cfg.edgePort}:8000"
        "${toString cfg.httpsPort}:9443"
      ];
      volumes = [
        "${cfg.dataDir}:/data"
        "/run/podman/podman.sock:/var/run/docker.sock"
      ];
      extraOptions = [ "--name=portainer" ];
    };

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [
      cfg.httpPort
      cfg.httpsPort
      cfg.edgePort
    ];
  };
}
