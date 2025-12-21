##
# Module: servers/qbittorrent-vpn
# Purpose: qBittorrent with built-in WireGuard VPN container via Podman.
# Key options: profiles.services.qbittorrent-vpn (enable, dataDir, downloadsDir, httpPort, vpnType, lanNetwork, nameServers).
# Dependencies: virtualisation.oci-containers (backend = podman).
# Note: Runs in privileged mode for VPN functionality.
{
  lib,
  config,
  ...
}: let
  cfg = config.profiles.services.qbittorrent-vpn;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.profiles.services.qbittorrent-vpn = {
    enable = mkEnableOption "qBittorrent with WireGuard VPN container";

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/qbittorrent-vpn";
      description = "Directory for qBittorrent configuration";
    };

    downloadsDir = mkOption {
      type = types.path;
      default = "/var/lib/qbittorrent-vpn/downloads";
      description = "Directory for downloads";
    };

    httpPort = mkOption {
      type = types.port;
      default = 8080;
      description = "Port for qBittorrent web UI";
    };

    incomingPort = mkOption {
      type = types.port;
      default = 57529;
      description = "Port for incoming BitTorrent connections";
    };

    timezone = mkOption {
      type = types.str;
      default = "Europe/Moscow";
      description = "Container timezone";
    };

    vpnEnabled = mkOption {
      type = types.bool;
      default = true;
      description = "Enable VPN (requires WireGuard config in dataDir)";
    };

    vpnType = mkOption {
      type = types.enum ["wireguard" "openvpn"];
      default = "wireguard";
      description = "VPN type (wireguard or openvpn)";
    };

    lanNetwork = mkOption {
      type = types.str;
      default = "192.168.1.0/24";
      description = "LAN network CIDR for web UI access (e.g., 192.168.1.0/24)";
    };

    nameServers = mkOption {
      type = types.str;
      default = "9.9.9.9,149.112.112.112";
      description = "DNS servers (comma-separated)";
    };
  };

  config = mkIf cfg.enable {
    # Ensure data directories exist
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
      "d ${cfg.downloadsDir} 0755 root root -"
    ];

    virtualisation.oci-containers.containers.qbittorrent-vpn = {
      # Disabled by default - start manually with: sudo podman start qbittorrent-vpn
      autoStart = false;
      image = "dyonr/qbittorrentvpn";
      environment = {
        TZ = cfg.timezone;
        PUID = "1000";
        PGID = "100";
        VPN_ENABLED =
          if cfg.vpnEnabled
          then "yes"
          else "no";
        VPN_TYPE = cfg.vpnType;
        WEBUI_PORT_ENV = toString cfg.httpPort;
        INCOMING_PORT_ENV = toString cfg.incomingPort;
        NAME_SERVERS = cfg.nameServers;
        LAN_NETWORK = cfg.lanNetwork;
      };
      ports = [
        "${toString cfg.httpPort}:${toString cfg.httpPort}"
        "${toString cfg.incomingPort}:${toString cfg.incomingPort}"
        "${toString cfg.incomingPort}:${toString cfg.incomingPort}/udp"
      ];
      volumes = [
        "${cfg.dataDir}:/config"
        "${cfg.downloadsDir}:/downloads"
      ];
      extraOptions = [
        "--name=qbittorrent-vpn"
        "--privileged"
      ];
    };

    # Open firewall ports
    networking.firewall = {
      allowedTCPPorts = [cfg.httpPort cfg.incomingPort];
      allowedUDPPorts = [cfg.incomingPort];
    };
  };
}
