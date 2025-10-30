##
# Module: monitoring/loki
# Purpose: Grafana Loki log aggregation with local filesystem storage.
# Key options: monitoring.loki.enable, monitoring.loki.retentionDays, monitoring.loki.port
{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.monitoring.loki or {};
in {
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
            index = { prefix = "index_"; period = "24h"; };
          }
        ];
        ruler = {
          rule_path = "/var/lib/loki/rules-temp";
          storage = { type = "local"; local.directory = "/var/lib/loki/rules"; };
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

    # Per-interface firewall opening if requested
    networking.firewall.interfaces = mkIf cfg.openFirewall (
      lib.genAttrs cfg.firewallInterfaces (iface: { allowedTCPPorts = [ cfg.port ]; })
    );
  };
}
