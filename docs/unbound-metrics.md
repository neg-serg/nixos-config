# Unbound DNS Metrics: Prometheus + Grafana

Purpose: instrument the local Unbound resolver for quality monitoring — response time, DNSSEC validation rate, cache hits/miss and related DNS health signals. Works with the DNS stack in this repo: apps → systemd‑resolved (127.0.0.53) → AdGuardHome (127.0.0.1:53) → Unbound (127.0.0.1:5353).

## What this wiring does

- Enables Unbound extended statistics and `unbound-control` on localhost (127.0.0.1:8953) for metric scraping.
- Runs Prometheus Unbound exporter (default: 127.0.0.1:9167) to translate Unbound stats into Prometheus metrics.
- Adds a Prometheus scrape job `unbound` and a Grafana Prometheus datasource so metrics are queryable out of the box.

This keeps all control and scrape endpoints bound to localhost by default. No firewall exposure is required.

## Enabling (NixOS snippets)

If you use the `roles.homelab` role in this repo, Unbound is already enabled and configured as upstream for AdGuardHome. To collect metrics, enable the exporter and scrape job and add Prometheus to Grafana:

```nix
{ lib, config, ... }: {
  # Unbound metrics exporter (localhost only)
  services.prometheus.exporters.unbound = {
    enable = true;
    port = 9167;
    openFirewall = false; # keep local only
  };

  # Prometheus server with unbound scrape job
  services.prometheus = {
    enable = true;
    scrapeConfigs = [
      {
        job_name = "unbound";
        static_configs = [ {
          targets = [ "127.0.0.1:${toString config.services.prometheus.exporters.unbound.port}" ];
        } ];
      }
    ];
  };

  # Grafana: add Prometheus datasource (Loki is provisioned elsewhere)
  services.grafana.provision.datasources.settings.datasources = [
    {
      name = "Prometheus";
      type = "prometheus";
      access = "proxy";
      url = "http://127.0.0.1:${toString config.services.prometheus.port}";
      isDefault = false;
    }
  ];
}
```

Repo module details:

- The Unbound profile sets `extended-statistics: yes` and enables `remote-control` on `127.0.0.1:8953` without TLS certificates. This is sufficient for the exporter. If you want TLS on the control socket, configure Unbound control certs and pass the corresponding flags to the exporter; keep the exporter and control socket on loopback for safety.

## Verify locally

- Exporter endpoint: `curl -s http://127.0.0.1:9167/metrics | head`
- Unbound control (no reset): `unbound-control -c /etc/unbound/unbound.conf stats_noreset | head`
- Prometheus target up: open `http://<host>:9090/targets` and check the `unbound` job.

## Grafana: panels and example queries

Metric names vary by exporter and Unbound version. Use Grafana’s query autocomplete for the `unbound_` prefix and adapt these examples to what you see.

- Response time (p50/p95). If histogram buckets are available as `unbound_histogram_request_time_seconds_bucket`:

  - p50: `histogram_quantile(0.5, sum by (le) (rate(unbound_histogram_request_time_seconds_bucket[5m])))`
  - p95: `histogram_quantile(0.95, sum by (le) (rate(unbound_histogram_request_time_seconds_bucket[5m])))`

  If the exporter does not expose latency histograms, use the already-present Blackbox DNS probe instead:

  - `probe_duration_seconds{job="blackbox-dns"}`

- DNSSEC validation rate (secure vs bogus):

  - `sum(rate(unbound_num_answer_secure_total[5m])) /
    (sum(rate(unbound_num_answer_secure_total[5m])) + sum(rate(unbound_num_answer_bogus_total[5m])))`

- Cache efficiency:

  - Hits: `sum(rate(unbound_num_cachehits_total[5m]))`
  - Misses: `sum(rate(unbound_num_cachemiss_total[5m]))`
  - Hit ratio: `sum(rate(unbound_num_cachehits_total[5m])) / (sum(rate(unbound_num_cachehits_total[5m])) + sum(rate(unbound_num_cachemiss_total[5m])))`

- Traffic and quality (optional):

  - QPS: `sum(rate(unbound_num_queries_total[5m]))`
  - By RCODE: `sum by (rcode) (rate(unbound_num_answer_rcode_total[5m]))`
  - By QTYPE: `sum by (type) (rate(unbound_num_query_type_total[5m]))`

## Security notes

- `remote-control` is bound to `127.0.0.1` and `control-use-cert: no` by default in this repo. This is safe on single-host setups where the exporter is local. Do not expose 8953/TCP to the network.
- For multi-host scraping or elevated assurance, enable Unbound control TLS (generate cert/key pair) and run the exporter with TLS parameters, still bound to loopback.

## Troubleshooting

- Exporter up but no metrics: verify `unbound-control status` works as the exporter’s service user; ensure `remote-control` is enabled and the socket listens on `127.0.0.1:8953`.
- No latency histogram: your exporter/Unbound may not provide buckets — use Blackbox DNS `probe_duration_seconds` until histograms are available.
- Zero DNSSEC secure counts: confirm `servicesProfiles.unbound.dnssec.enable = true;` and that upstreams support DNSSEC when using forwarding.

