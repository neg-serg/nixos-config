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

  environment.variables = {
    ALL_PROXY = "socks5://127.0.0.1:10808";
    all_proxy = "socks5://127.0.0.1:10808";
    http_proxy = "socks5://127.0.0.1:10808";
    https_proxy = "socks5://127.0.0.1:10808";
    HTTP_PROXY = "socks5://127.0.0.1:10808";
    HTTPS_PROXY = "socks5://127.0.0.1:10808";
    no_proxy = "localhost,127.0.0.1,::1,.local";
    NO_PROXY = "localhost,127.0.0.1,::1,.local";
  };

  # Force git / libgit2 (used by nix flakes) through the SOCKS5 proxy
  environment.etc."gitconfig".text = ''
    [http "https://github.com"]
      proxy = socks5://127.0.0.1:10808
    [http "https://flakehub.com"]
      proxy = socks5://127.0.0.1:10808
    [http "http://"]
      proxy = socks5://127.0.0.1:10808
    [http "https://"]
      proxy = socks5://127.0.0.1:10808
  '';

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
        PROXY_URL="socks5://phone:$PW@127.0.0.1:10808"
        {
          printf 'ALL_PROXY=%s\n' "$PROXY_URL"
          printf 'all_proxy=%s\n' "$PROXY_URL"
          printf 'http_proxy=%s\n' "$PROXY_URL"
          printf 'https_proxy=%s\n' "$PROXY_URL"
          printf 'HTTP_PROXY=%s\n' "$PROXY_URL"
          printf 'HTTPS_PROXY=%s\n' "$PROXY_URL"
          printf 'no_proxy=localhost,127.0.0.1,::1,.local\n'
          printf 'NO_PROXY=localhost,127.0.0.1,::1,.local\n'
        } > /run/secrets/xray-proxy-env.tmp
        mv /run/secrets/xray-proxy-env.tmp /run/secrets/xray-proxy-env
        chmod 400 /run/secrets/xray-proxy-env
        chown neg:neg /run/secrets/xray-proxy-env
      fi
    '';
  };
}
