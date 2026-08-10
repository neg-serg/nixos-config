{ pkgs, lib, config, ... }:
# Full-TUN proxy: routes all non-private traffic through the sing-box
# VLESS/Hysteria2 node over the sb0 TUN interface. Toggle:
#   tun on | tun off | tun status   (or systemctl start|stop sing-box-tun)
# No autostart — manual toggle only (like xray.service).
# Routing: pref 100 → VPN server IPs direct (main), pref 150 → private nets
# direct (main), pref 200 → table 200 → default dev sb0; DNS via resolvectl.
let
  cfg = config.features.net.proxy or { };
in
lib.mkIf cfg.enable {
  systemd.services.sing-box-tun = {
    description = "sing-box full-TUN proxy (all traffic via sb0)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    # Manual toggle only — no autostart (would hijack all traffic at boot)
    wantedBy = lib.mkForce [ ];
    path = [
      pkgs.iproute2 # ip rules/routes
      pkgs.systemd # resolvectl
      pkgs.python3 # TUN config generation
      pkgs.sing-box # run + config check
    ];
    serviceConfig = {
      Type = "simple";
      ExecStartPre = "${./sing-box-tun-up.sh}";
      ExecStart = "${lib.getExe pkgs.sing-box} run -c /run/sing-box-tun/config.json";
      ExecStopPost = "${./sing-box-tun-down.sh}";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
