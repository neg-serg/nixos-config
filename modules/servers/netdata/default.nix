##
# Module: servers/netdata
# Purpose: Netdata real-time performance monitoring container via Podman.
# Key options: profiles.services.netdata (enable, dataDir, httpPort).
# Dependencies: virtualisation.oci-containers (backend = podman).
# Note: Uses host network mode and privileged capabilities for full system monitoring.
{
  lib,
  config,
  ...
}: let
  cfg = config.profiles.services.netdata;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.profiles.services.netdata = {
    enable = mkEnableOption "Netdata real-time performance monitoring container";

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/netdata";
      description = "Directory for Netdata configuration and data";
    };

    httpPort = mkOption {
      type = types.port;
      default = 19999;
      description = "Port for Netdata web UI";
    };

    timezone = mkOption {
      type = types.str;
      default = config.time.timeZone;
      description = "Container timezone";
    };
  };

  config = mkIf cfg.enable {
    # Ensure data directories exist
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
      "d ${cfg.dataDir}/config 0755 root root -"
      "d ${cfg.dataDir}/lib 0755 root root -"
      "d ${cfg.dataDir}/cache 0755 root root -"
    ];

    virtualisation.oci-containers.containers.netdata = {
      # Disabled by default - start manually with: sudo podman start netdata
      autoStart = false;
      image = "netdata/netdata";
      environment = {
        TZ = cfg.timezone;
      };
      volumes = [
        "${cfg.dataDir}/config:/etc/netdata"
        "${cfg.dataDir}/lib:/var/lib/netdata"
        "${cfg.dataDir}/cache:/var/cache/netdata"
        "/:/host/root:ro,rslave"
        "/etc/passwd:/host/etc/passwd:ro"
        "/etc/group:/host/etc/group:ro"
        "/etc/localtime:/etc/localtime:ro"
        "/proc:/host/proc:ro"
        "/sys:/host/sys:ro"
        "/etc/os-release:/host/etc/os-release:ro"
        "/var/log:/host/var/log:ro"
        "/run/podman/podman.sock:/var/run/docker.sock:ro"
      ];
      extraOptions = [
        "--name=netdata"
        "--network=host"
        "--cap-add=SYS_PTRACE"
        "--cap-add=SYS_ADMIN"
      ];
    };

    # Open firewall port for web UI
    networking.firewall.allowedTCPPorts = [cfg.httpPort];
  };
}
