{
  config,
  lib,
  ...
}:
let
  cfg = config.features.net.lan-proxy;
in
{
    type = lib.types.listOf lib.types.str;
    default = [
      "10.0.0.0/8"
      "172.16.0.0/12"
      "192.168.0.0/16"
    ];
    description = "Subnets allowed to use the LAN SOCKS5 proxy (port 10809). Default: RFC 1918 private ranges only.";
  };

  config = lib.mkIf cfg.enable {
    # LAN SOCKS5 now served directly by Xray (second inbound on 0.0.0.0:10809).
    # The Xray config at ~/.config/sing-box-tun/config.json must include:
    #   { "listen": "0.0.0.0", "port": 10809, "protocol": "socks", "settings": { "udp": true } }
    # No separate dante process needed — Xray handles both local (127.0.0.1:10808)
    # and LAN (0.0.0.0:10809) SOCKS5 without authentication.

    # Restrict access per allowedSubnets via iptables rules instead of
    # blanket allowedTCPPorts. Uses nixos-fw-accept so matched traffic
    # is accepted; unmatched traffic hits the default INPUT DROP policy.
    networking.firewall.extraCommands = lib.concatMapStringsSep "\n" (subnet:
      "iptables -A nixos-fw -p tcp --dport 10809 -s ${subnet} -j nixos-fw-accept"
    ) cfg.allowedSubnets;
  };
}
