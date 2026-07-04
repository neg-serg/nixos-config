##
# Module: monitoring/loki
# Purpose: Grafana Loki log aggregation with local filesystem storage and alert rules.
# Key options: monitoring.loki.enable, monitoring.loki.retentionDays, monitoring.loki.port
{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  cfg = config.monitoring.loki or { };

  # Alert rules ported from legacy Salt config (loki-alert-rules.yaml.j2)
  alertRulesFile = pkgs.writeText "loki-alert-rules.yaml" ''
    groups:
      - name: salt-monitor-rules
        interval: 30s
        rules:
          - alert: ErrorBurst
            expr: |
              sum by (unit) (
                count_over_time({job="systemd-journal"} |= "level=error" [1m])
              ) > 10
            for: 5m
            labels:
              severity: warning
              source: loki
            annotations:
              summary: "Error burst from {{ $labels.unit }}"
              description: "{{ $value }} errors in last minute"

          - alert: SSHBruteForce
            expr: |
              sum by (source_ip) (
                count_over_time({unit="sshd.service"} |~ "Failed password|Invalid user" [5m])
              ) > 5
            for: 5m
            labels:
              severity: critical
              source: loki
            annotations:
              summary: "SSH brute force from {{ $labels.source_ip }}"
              description: "{{ $value }} failed attempts in 5 minutes"

          - alert: OOMKiller
            expr: |
              count_over_time({job="systemd-journal"} |= "Out of memory: Killed process" [1m]) > 0
            for: 0m
            labels:
              severity: critical
              source: loki
            annotations:
              summary: "OOM killer activated"
              description: "A process was killed by the OOM killer"
  '';
in
{
  options.monitoring.loki = {
    enable = mkEnableOption "Enable Grafana Loki (log aggregator).";

    port = mkOption {
      type = types.port;
      default = 3100;
      description = "HTTP listen port for Loki server.";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "HTTP listen address for Loki server (default: localhost).";
    };

    retentionDays = mkOption {
      type = types.int;
      default = 30;
      description = "Log retention period in days (filesystem storage).";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open firewall for Loki HTTP port.";
    };

    firewallInterfaces = mkOption {
      type = types.listOf types.str;
      default = [ "br0" ];
      description = "Interfaces to allow Loki port on when openFirewall is true.";
    };
  };

  config = mkIf (cfg.enable or false) {
    services.loki = {
      enable = true;
      # Keep local-only; expose UI/API on localhost
      configuration = {
        auth_enabled = false;
        server = {
          http_listen_address = cfg.listenAddress;
          http_listen_port = cfg.port;
          grpc_listen_port = 0;
        };
        common = {
          path_prefix = "/var/lib/loki";
          storage = {
            filesystem = {
              chunks_directory = "/var/lib/loki/chunks";
              rules_directory = "/var/lib/loki/rules";
            };
          };
          replication_factor = 1;
          ring = {
            instance_addr = "127.0.0.1";
            kvstore.store = "inmemory";
          };
        };
        schema_config.configs = [
          {
            from = "2020-10-24";
            store = "boltdb-shipper";
            object_store = "filesystem";
            schema = "v13";
            index = {
              prefix = "index_";
              period = "24h";
            };
          }
        ];
        ruler = {
          rule_path = "/var/lib/loki/rules-temp";
          storage = {
            type = "local";
            local.directory = "/var/lib/loki/rules";
          };
          alertmanager_url = "http://127.0.0.1:9093";
        };
        analytics.reporting_enabled = false;
        limits_config = {
          allow_structured_metadata = false;
          retention_period = "${toString cfg.retentionDays}d";
        };
        table_manager = {
          retention_deletes_enabled = true;
          retention_period = "${toString cfg.retentionDays}d";
        };
      };
    };

    # Alert rules for Loki ruler — placed in the rules directory via tmpfiles
    systemd.tmpfiles.rules = lib.mkAfter [
      "d /var/lib/loki/rules 0755 loki loki - -"
      "C /var/lib/loki/rules/loki-alert-rules.yaml 0644 loki loki - ${alertRulesFile}"
    ];

    # Per-interface firewall opening if requested
    networking.firewall.interfaces = mkIf cfg.openFirewall (
      lib.genAttrs cfg.firewallInterfaces (_iface: {
        allowedTCPPorts = [ cfg.port ];
      })
    );
  };
}
