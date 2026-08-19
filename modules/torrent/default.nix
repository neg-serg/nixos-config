{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "torrent";
  packages = [
    pkgs.transmission_4 # primary BitTorrent client/daemon
    pkgs.rustmission # CLI Transmission client written in Rust
    pkgs.stig # TUI Transmission client with vi-style keybindings
    pkgs.tewi # Text-based client for Transmission/qBittorrent/Deluge daemons
    pkgs.curl # HTTP helper for tracker scripts
    pkgs.jq # parse Transmission RPC JSON responses
  ];
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
