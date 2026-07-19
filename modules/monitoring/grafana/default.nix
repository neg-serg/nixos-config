##
# Module: monitoring/grafana
# Purpose: Grafana with a preprovisioned Loki datasource. LAN-exposed with per-interface firewall.
# Key options: monitoring.grafana.enable, monitoring.grafana.port, monitoring.grafana.listenAddress,
#              monitoring.grafana.openFirewall, monitoring.grafana.firewallInterfaces
{
  lib,
  config,
  inputs,
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

    # Grafana hardening: disable external calls and telemetry
    # (moved from hosts/odin/services.nix)
    services.grafana.settings = {
      analytics = {
        reporting_enabled = false;
        check_for_updates = false;
      };
      users.allow_gravatar = false;
      news.news_feed_enabled = false;
      dashboards.min_refresh_interval = "10s";
      snapshots.external_enabled = false;
      plugins = {
        enable_alpha = false;
      };
    };

    # Restrict Grafana to loopback-only egress
    systemd.services.grafana = {
      environment.GF_FEATURE_TOGGLES_DISABLE = "preinstallAutoUpdate";
      serviceConfig = {
        IPAddressDeny = "any";
        IPAddressAllow = [
          "127.0.0.0/8"
          "::1/128"
        ];
      };
    };
    # Clean plugins directory and provisioning JSON dir on activation
    systemd.tmpfiles.rules = lib.mkAfter [
      "R /var/lib/grafana/plugins - - - - -"
      "d /var/lib/grafana/plugins 0750 grafana grafana - -"
      "d /etc/grafana/provisioning/dashboards/json 0755 grafana grafana - -"
    ];

    # Provision local dashboards (repo-level dashboard JSON files)
    services.grafana.provision.dashboards.settings.providers = lib.mkAfter [
      {
        name = "local-json";
        orgId = 1;
        type = "file";
        disableDeletion = false;
        editable = true;
        options.path = inputs.self + "/files/dashboards";
      }
    ];

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

    # nothing else
  };
}

