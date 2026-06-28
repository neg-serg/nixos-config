##
# Module: system/net/proxy
# Purpose: V2Ray/Xray proxy utilities.
# Key options: none.
# Dependencies: pkgs, sops.
#
# The proxy password is stored in a sops-encrypted file and exposed to
# nix-daemon and the user shell via a generated env file at runtime.
#
# Bootstrap note: on a fresh system the Xray config doesn't exist yet.
# Copy or create it at ~/.config/sing-box-tun/config.json (from the old
# system), then:
#   sudo systemctl start xray
#   nixos-rebuild switch
{
  pkgs,
  lib,
  config,
  ...
}:
let
  secretsDir = ../../../secrets/home;
  hasSopsFile = builtins.pathExists "${secretsDir}/xray-proxy-password.sops.yaml";
  xrayConfigFile = "/home/neg/.config/sing-box-tun/config.json";
  hasXrayConfig = builtins.pathExists xrayConfigFile;
  proxyEnabled = hasSopsFile && hasXrayConfig;
in
{
  environment.systemPackages = [
    pkgs.xray # VLESS/Reality-capable proxy core
  ];

  # Sops-managed proxy + Xray service — only active when both the sops
  # file and xray config exist.
  sops = lib.mkIf hasSopsFile {
    secrets."xray_proxy_password" = {
      format = "yaml";
      sopsFile = "${secretsDir}/xray-proxy-password.sops.yaml";
      key = "xray_proxy_password";
    };
  };

  # Xray local SOCKS5 proxy (auto-starts)
  systemd.services.xray = lib.mkIf hasXrayConfig {
    description = "Xray local SOCKS5 proxy (127.0.0.1:10808)";
    after = [ "network-online.target" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "simple";
      User = "neg";
      ExecStart = "${pkgs.xray}/bin/xray run -config ${xrayConfigFile}";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # Inject proxy env into nix-daemon
  systemd.services.nix-daemon = lib.mkIf proxyEnabled {
    serviceConfig.EnvironmentFile = [ "/run/secrets/xray-proxy-env" ];
  };

  # Generate xray-proxy-env from decrypted sops password (oneshot, runs at boot)
  systemd.services.xray-proxy-env = lib.mkIf hasSopsFile {
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
