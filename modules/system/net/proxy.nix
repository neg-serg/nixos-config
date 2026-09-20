{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.net.proxy;
in
lib.mkIf cfg.enable {
  environment.systemPackages = [
    pkgs.xray # VLESS/Reality-capable proxy core
  ];

  systemd.services.xray = {
    description = "Xray local SOCKS5 proxy (127.0.0.1:10808)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    # No autostart, and deliberately no ExecStartPre: it used to run
    # `fuser -k 10808/tcp`, which killed the user's sing-box proxy (also on
    # 10808) on every activation — each `nh os switch` took API access down
    # with it, then the unit crash-looped until the next manual restart. The
    # xray unit stays manual; picking a port that does not clash with the
    # sing-box SOCKS inbound is the caller's job.
    wantedBy = lib.mkForce [ ];
    serviceConfig = {
      Type = "simple";
      User = "neg";
      ExecStart = "${lib.getExe pkgs.xray} run -config /home/neg/.config/sing-box-tun/config.json";
    };
  };
}
