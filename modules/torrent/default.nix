{lib, config, pkgs, ...}: let
  enabled = config.features.torrent.enable or false;
  packages = [
    pkgs.transmission_4 # primary BitTorrent client/daemon
    pkgs.bitmagnet # torrent indexer for private trackers
    pkgs.neg.bt_migrate # migration tool between torrent clients
    pkgs.rustmission # CLI Transmission client written in Rust
    pkgs.curl # HTTP helper for tracker scripts
    pkgs.jq # parse Transmission RPC JSON responses
    pkgs.jackett # meta-indexer to feed torrent search
  ];
in {
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
