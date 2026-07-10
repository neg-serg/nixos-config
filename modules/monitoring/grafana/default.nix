##
# Module: monitoring/grafana
# Purpose: Grafana with a preprovisioned Loki datasource. LAN-exposed with per-interface firewall.
# Key options: monitoring.grafana.enable, monitoring.grafana.port, monitoring.grafana.listenAddress,
#              monitoring.grafana.openFirewall, monitoring.grafana.firewallInterfaces
{
  lib,
  config,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  cfg = config.monitoring.grafana or { };
  lokiPort = config.monitoring.loki.port or 3100;
  lokiUrl = "http://127.0.0.1:${toString lokiPort}";
in
{
  options.monitoring.grafana = {
    enable = mkEnableOption "Enable Grafana with Loki datasource.";

    port = mkOption {
      type = types.port;
      default = 3030; # avoid conflict with AdGuardHome on :3000
      description = "Grafana HTTP port.";
    };

    # Admin credentials
    adminUser = mkOption {
      type = types.str;
      default = "admin";
      description = "Grafana admin username.";
    };
    adminPasswordFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to a file containing the Grafana admin password (use with SOPS).";
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
      settings.security = {
        admin_user = cfg.adminUser;
      }
      // (lib.optionalAttrs (cfg.adminPasswordFile != null) {
        admin_password = "${"$"}__file{${cfg.adminPasswordFile}}";
      });
      # Provisioning path — Grafana looks for provisioning config files here
      settings.paths.provisioning = "/etc/grafana/provisioning";

      # Provision a Loki datasource so Explore works out of the box
      provision = {
        enable = true;
        datasources.settings.datasources = [
          {
            uid = "loki";
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

    # Dashboard provider — tells Grafana where to find dashboard JSON files
    environment.etc."grafana/provisioning/dashboards/salt.yaml" = {
      target = "/etc/grafana/provisioning/dashboards/salt.yaml";
      text = ''
        apiVersion: 1
        providers:
          - name: salt
            type: file
            options:
              path: /etc/grafana/provisioning/dashboards/json
              foldersFromFilesStructure: false
            updateIntervalSeconds: 30
            allowUiUpdates: true
      '';
    };

    # Per-interface firewall openings
    networking.firewall.interfaces = lib.mkMerge [
      (mkIf cfg.openFirewall (
        lib.genAttrs cfg.firewallInterfaces (_iface: {
          allowedTCPPorts = [ cfg.port ];
        })
      ))
    ];



    # tmpfiles rules for Grafana dashboard provisioning
    systemd.tmpfiles.rules = lib.mkAfter [
      "d /etc/grafana/provisioning/dashboards/json 0755 grafana grafana - -"
    ];

    # nothing else
  };
}
