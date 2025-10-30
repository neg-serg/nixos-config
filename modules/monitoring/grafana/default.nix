##
# Module: monitoring/grafana
# Purpose: Grafana with a preprovisioned Loki datasource. LAN-exposed with per-interface firewall.
# Key options: monitoring.grafana.enable, monitoring.grafana.port, monitoring.grafana.listenAddress,
#              monitoring.grafana.openFirewall, monitoring.grafana.firewallInterfaces
{ lib, config, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.monitoring.grafana or {};
  lokiPort = config.monitoring.loki.port or 3100;
  lokiUrl = "http://127.0.0.1:${toString lokiPort}";
in {
  options.monitoring.grafana = {
    enable = mkEnableOption "Enable Grafana with Loki datasource.";

    port = mkOption {
      type = types.port;
      default = 3030; # avoid conflict with AdGuardHome on :3000
      description = "Grafana HTTP port.";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Grafana HTTP listen address.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall for Grafana port on selected interfaces.";
    };

    firewallInterfaces = mkOption {
      type = types.listOf types.str;
      default = [ "br0" ];
      description = "Interfaces where Grafana port is allowed when openFirewall is true.";
    };
  };

  config = mkIf (cfg.enable or false) {
    services.grafana = {
      enable = true;
      settings.server = {
        http_port = cfg.port;
        http_addr = cfg.listenAddress;
        domain = config.networking.hostName or "grafana.local";
      };
      # Provision a Loki datasource so Explore works out of the box
      provision = {
        enable = true;
        datasources.settings.datasources = [
          {
            name = "Loki";
            type = "loki";
            access = "proxy";
            url = lokiUrl;
            isDefault = true;
            jsonData = { }; # keep minimal
          }
        ];
      };
    };

    # Per-interface firewall opening if requested
    networking.firewall.interfaces = mkIf cfg.openFirewall (
      lib.genAttrs cfg.firewallInterfaces (iface: { allowedTCPPorts = [ cfg.port ]; })
    );
  };
}

