{
  config,
  lib,
  ...
}:
let
  cfg = config.features.net.lan-proxy;
in
lib.mkIf cfg.enable {
  # LAN SOCKS5 now served directly by Xray (second inbound on 0.0.0.0:10809).
  # The Xray config at ~/.config/sing-box-tun/config.json must include:
  #   { "listen": "0.0.0.0", "port": 10809, "protocol": "socks", "settings": { "udp": true } }
  # No separate dante process needed — Xray handles both local (127.0.0.1:10808)
  # and LAN (0.0.0.0:10809) SOCKS5 without authentication.

  networking.firewall.allowedTCPPorts = [ 10809 ];
}
