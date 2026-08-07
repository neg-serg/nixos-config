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

  systemd.services.nix-daemon.serviceConfig.EnvironmentFile = lib.mkAfter [
    "-/run/secrets/xray-proxy-env"
  ];

  systemd.services.xray-proxy-env = {
    description = "Generate proxy environment file for nix-daemon";
    before = [ "nix-daemon.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.curl ]; # probe connectivity through the proxy
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # Only hand the daemon a proxy that actually forwards traffic.
      # A dead proxy (VPN down, or sing-box up with a dead upstream) poisons
      # every nix fetch/substitution and hangs builds (2026-08-07 incident).
      if timeout 6 curl --socks5-hostname 127.0.0.1:10808 --max-time 5 -fsS \
          https://ifconfig.me > /dev/null 2>&1; then
        # socks5h (remote DNS): local resolution would hand the proxy broken
        # IPv6-first addresses and TLS handshakes fail (see runbooks/proxy.md).
        printf '%s\n' 'ALL_PROXY=socks5h://127.0.0.1:10808' > /run/secrets/xray-proxy-env.tmp
      else
        : > /run/secrets/xray-proxy-env.tmp
      fi
      mv /run/secrets/xray-proxy-env.tmp /run/secrets/xray-proxy-env
      chmod 400 /run/secrets/xray-proxy-env
      chown neg:neg /run/secrets/xray-proxy-env
    '';
  };
}
