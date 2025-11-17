# Nextcloud Monitoring: Blackbox + PHP-FPM metrics

Purpose: monitor Nextcloud availability and latency via Blackbox, and PHP-FPM pool health via the
Prometheus php-fpm exporter. This complements the existing Loki logs and system metrics.

## What’s included in this repo

- Blackbox HTTPS probe to `https://telfir/status.php` with permissive TLS (LAN/self-signed). Exposed
  as job `blackbox-https-insecure` pointing to the Blackbox exporter on localhost.
- Optional PHP-FPM exporter configured to scrape the Nextcloud pool through its unix socket with
  status path `/status`.
- Prometheus scrape job `phpfpm` for the exporter.

All endpoints remain on localhost by default; nothing is exposed on the LAN.

## NixOS snippets used here

Blackbox probe (already in host config):

```nix
{
  services.prometheus.exporters.blackbox = {
    enable = true;
    port = 9115;
    openFirewall = true; # limited to br0 via firewallFilter in this repo
  };

  services.prometheus.scrapeConfigs = [
    {
      job_name = "blackbox-https-insecure";
      metrics_path = "/probe";
      params.module = [ "http_2xx_insecure" ];
      static_configs = [ { targets = [ "https://telfir/status.php" ]; } ];
      relabel_configs = [
        { source_labels = [ "__address__" ]; target_label = "__param_target"; }
        { source_labels = [ "__param_target" ]; target_label = "instance"; }
        { target_label = "__address__"; replacement = "127.0.0.1:9115"; }
      ];
    }
  ];
}
```

PHP-FPM exporter (optional, enabled here):

```nix
{
  # Nextcloud PHP-FPM pool must expose status path
  services.phpfpm.pools.nextcloud.settings."pm.status_path" = "/status";

  services.prometheus.exporters."php-fpm" = {
    enable = true;
    openFirewall = false; # keep local-only
    extraFlags = [
      "--phpfpm.scrape-uri=unix:///run/phpfpm/nextcloud.sock;/status"
    ];
  };

  services.prometheus.scrapeConfigs = [
    {
      job_name = "phpfpm";
      static_configs = [ { targets = [ "127.0.0.1:${toString config.services.prometheus.exporters."php-fpm".port}" ]; } ];
    }
  ];
}
```

## Verify locally

- Blackbox probe: open Prometheus Targets and check `blackbox-https-insecure` instance
  `https://telfir/status.php`.
- PHP-FPM exporter: `curl -s http://127.0.0.1:9253/metrics | head`.

## Grafana: useful queries

Use autocomplete for prefixes `probe_` and `php_fpm_` as metric names vary slightly per exporter
version.

- Nextcloud HTTPS latency (panel/alert):

  - `probe_duration_seconds{job="blackbox-https-insecure", instance="https://telfir/status.php"}`

- PHP-FPM pool health:

  - Active processes: `php_fpm_processes{state="active"}` or `php_fpm_active_processes`
  - Idle processes: `php_fpm_processes{state="idle"}` or `php_fpm_idle_processes`
  - Listen queue depth: `php_fpm_listen_queue`
  - Max children reached: `increase(php_fpm_max_children_reached[1h])`
  - Accepted connections: `rate(php_fpm_accepted_connections_total[5m])`

## Alerts (examples)

- Probe fail (already provided in repo for all blackbox HTTP jobs):

  - `probe_success{job=~"blackbox-http|blackbox-https-insecure"} == 0` for 1m

- High Nextcloud latency (example):

  - `probe_duration_seconds{job="blackbox-https-insecure", instance="https://telfir/status.php"} > 2`
    for 5m

Adjust thresholds to your environment.
