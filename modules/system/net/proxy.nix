##
# Module: system/net/proxy
# Purpose: V2Ray/V2RayA proxy utilities.
# Key options: none.
# Dependencies: pkgs.
{
  pkgs,
  lib,
  ...
}:
{
  environment.systemPackages = [
    # pkgs.sing-box # proxy core supporting VLESS/Reality and tun
    pkgs.xray # VLESS/Reality-capable proxy core
  ];

  # TUN service for sing-box VLESS Reality (config expected at /run/user/1000/secrets/vless-reality-singbox-tun.json)
  # systemd.services."sing-box-tun" = {
  systemd.services."sing-box-tun" = lib.mkIf false {
    description = "Sing-box VLESS Reality (tun, manual start)";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    wantedBy = [ ]; # manual start: systemctl start sing-box-tun
    serviceConfig = {
      RuntimeDirectory = "sing-box-tun";
      ExecStartPre = [
        "/run/current-system/sw/bin/test -f /run/user/1000/secrets/vless-reality-singbox-tun.json"
        "/run/current-system/sw/bin/sh -c '/run/current-system/sw/bin/ip rule del pref 100 2>/dev/null; /run/current-system/sw/bin/ip rule del pref 200 2>/dev/null; /run/current-system/sw/bin/ip route show table 200 default > /run/sing-box-tun/prev-default-route 2>/dev/null; /run/current-system/sw/bin/ip route del default table 200 2>/dev/null'"
      ];
      ExecStart = "${pkgs.sing-box}/bin/sing-box run -c /run/user/1000/secrets/vless-reality-singbox-tun.json"; # Universal proxy platform
      ExecStartPost = [
        "/run/current-system/sw/bin/sh -c '/run/current-system/sw/bin/ip rule add pref 100 to 204.152.223.171 lookup main'"
        "/run/current-system/sw/bin/sh -c '/run/current-system/sw/bin/ip route replace default dev sb0 table 200'"
        "/run/current-system/sw/bin/sh -c '/run/current-system/sw/bin/ip rule add pref 200 lookup 200'"
        "/run/current-system/sw/bin/ip route flush cache"
        "/run/current-system/sw/bin/resolvectl dns sb0 1.1.1.1 1.0.0.1"
        "/run/current-system/sw/bin/resolvectl domain sb0 \"~.\""
      ];
      ExecStopPost = [
        "/run/current-system/sw/bin/sh -c \"/run/current-system/sw/bin/ip rule del pref 200 2>/dev/null; /run/current-system/sw/bin/ip route del default dev sb0 table 200 2>/dev/null; if test -s /run/sing-box-tun/prev-default-route; then /run/current-system/sw/bin/ip route replace table 200 $(cat /run/sing-box-tun/prev-default-route); fi; /run/current-system/sw/bin/ip rule del pref 100 2>/dev/null; /run/current-system/sw/bin/ip route flush cache\""
        "/run/current-system/sw/bin/resolvectl revert sb0"
      ];
      Restart = "on-failure";
      CapabilityBoundingSet = [
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
        "CAP_NET_BIND_SERVICE"
      ];
      AmbientCapabilities = [
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
        "CAP_NET_BIND_SERVICE"
      ];
      NoNewPrivileges = false;
    };
  };
}
