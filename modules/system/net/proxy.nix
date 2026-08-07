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
    # No autostart: xray's ExecStartPre kills the sing-box proxy on 10808
    # every activation (nh os switch). User proxy is sing-box via ~/.local/bin/proxy.
    wantedBy = lib.mkForce [ ];
    serviceConfig = {
      Type = "simple";
      User = "neg";
      ExecStartPre = "${lib.getExe' pkgs.bash "bash"} -c '${lib.getExe' pkgs.psmisc "fuser"} -k 10808/tcp 2>/dev/null; true'";
      ExecStart = "${lib.getExe pkgs.xray} run -config /home/neg/.config/sing-box-tun/config.json";
    };
  };
}
