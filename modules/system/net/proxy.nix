##
# Module: system/net/proxy
# Purpose: V2Ray/Xray proxy utilities.
# Key options: none.
# Dependencies: pkgs, sops.
#
# The proxy password is stored in a sops-encrypted file and exposed to
# nix-daemon and the user shell via a sops template at runtime.
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
    templates."xray-proxy-env" = {
      content = ''
        ALL_PROXY=socks5://phone:{{ .xray_proxy_password }}@127.0.0.1:10808
      '';
      path = "/run/secrets/xray-proxy-env";
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

}
