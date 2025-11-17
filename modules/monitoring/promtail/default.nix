##
# Module: monitoring/promtail
# Purpose: Promtail log shipper with journal and /var/log scraping to local Loki.
# Key options: monitoring.promtail.enable
{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.monitoring.promtail or {};
  lokiPort = config.monitoring.loki.port or 3100;
  host = config.networking.hostName or "localhost";
in {
  options.monitoring.promtail.enable =
    mkEnableOption "Enable Promtail (ship logs to Loki); includes systemd-journal.";

  config = mkIf (cfg.enable or false) {
    services.promtail = {
      enable = true;
      configuration = {
        server = {
          http_listen_port = 9080;
          grpc_listen_port = 0;
        };
        positions.filename = "/var/cache/promtail/positions.yaml";
        clients = [{url = "http://127.0.0.1:${toString lokiPort}/loki/api/v1/push";}];
        scrape_configs = [
          # Systemd journal (persistent journal is already configured in host)
          {
            job_name = "journal";
            journal = {
              path = "/var/log/journal";
              max_age = "12h";
                labels = {
                  job = "systemd-journal";
                  inherit host;
                };
            };
            relabel_configs = [
              {
                source_labels = ["__journal__systemd_unit"];
                target_label = "unit";
              }
              {
                source_labels = ["__journal_priority"];
                target_label = "priority";
              }
              {
                source_labels = ["__journal__hostname"];
                target_label = "host";
              }
            ];
          }
          # Classic /var/log/*.log files
          {
            job_name = "varlogs";
            static_configs = [
              {
                targets = ["localhost"];
                labels = {
                  job = "varlogs";
                  __path__ = "/var/log/*.log";
                };
              }
            ];
          }
        ];
      };
    };
  };
}
