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

  sops.secrets."xray_proxy_password" = {
    format = "yaml";
    sopsFile = ../../../secrets/home/xray-proxy-password.sops.yaml;
    key = "xray_proxy_password";
  };

  systemd.services.xray = {
    description = "Xray local SOCKS5 proxy (127.0.0.1:10808)";
    after = [ "network-online.target" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "simple";
      User = "neg";
      ExecStart = "${pkgs.xray}/bin/xray run -config /home/neg/.config/sing-box-tun/config.json";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  systemd.services.nix-daemon.serviceConfig.EnvironmentFile = lib.mkAfter [ "-/run/secrets/xray-proxy-env" ];

  systemd.services.xray-proxy-env = {
    description = "Generate proxy environment file from sops secret";
    before = [ "nix-daemon.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      PW=$(cat /run/secrets/xray_proxy_password 2>/dev/null || true)
      if [ -n "$PW" ]; then
        printf 'ALL_PROXY=socks5://phone:%s@127.0.0.1:10808\n' "$PW" > /run/secrets/xray-proxy-env.tmp
        mv /run/secrets/xray-proxy-env.tmp /run/secrets/xray-proxy-env
        chmod 400 /run/secrets/xray-proxy-env
        chown neg:neg /run/secrets/xray-proxy-env
      fi
    '';
  };
}
