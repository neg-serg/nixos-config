{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = config.features.torrent.enable or false;
  prometheusEnabled = config.features.torrent.prometheus.enable or false;
  packages = [
    pkgs.transmission_4 # primary BitTorrent client/daemon
    pkgs.rustmission # CLI Transmission client written in Rust
    pkgs.curl # HTTP helper for tracker scripts
    pkgs.jq # parse Transmission RPC JSON responses
  ]
  ++ lib.optionals prometheusEnabled [
    pkgs.neg.transmission_exporter # Prometheus exporter for Transmission metrics
  ];
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
