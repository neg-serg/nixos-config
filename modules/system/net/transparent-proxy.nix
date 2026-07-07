{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.net.transparent-proxy;
in
lib.mkIf cfg.enable {
  # Must have the base Xray SOCKS5 proxy running
  features.net.proxy.enable = lib.mkDefault true;

  # Generate redsocks.conf with proxy auth from SOPS secret
  systemd.services.transparent-proxy-env = {
    description = "Generate redsocks.conf from sops proxy secret";
    before = [ "redsocks.service" ];
    wantedBy = [ "transparent-proxy.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
            PW=$(cat /run/secrets/xray_proxy_password 2>/dev/null || true)
            if [ -n "$PW" ]; then
              cat > /run/redsocks.conf <<EOF
      base {
          log_debug = off;
          log_info = off;
          daemon = off;
          redirector = iptables;
      }
      redsocks {
          local_ip = 127.0.0.1;
          local_port = 12345;
          ip = 127.0.0.1;
          port = 10808;
          type = socks5;
          login = "phone";
          password = "$PW";
      }
      EOF
              chmod 600 /run/redsocks.conf
            else
              echo "transparent-proxy-env: xray_proxy_password secret not available" >&2
              exit 1
            fi
    '';
  };

  # redsocks daemon — accepts transparently-redirected TCP and forwards via SOCKS5
  systemd.services.redsocks = {
    description = "Redsocks transparent TCP→SOCKS5 redirector";
    after = [
      "network-online.target"
      "xray.service"
      "transparent-proxy-env.service"
    ];
    wants = [
      "network-online.target"
      "transparent-proxy-env.service"
    ];
    wantedBy = [ "transparent-proxy.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.redsocks}/bin/redsocks -c /run/redsocks.conf";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # nftables rules — redirect root TCP traffic (nix-daemon) through redsocks.
  # User "neg" (xray) is excluded to avoid redirect loop.
  # Private/local nets are bypassed so LAN/loopback work without proxy.
  systemd.services.transparent-proxy-rules = {
    description = "nftables transparent redirect rules for proxy";
    after = [ "redsocks.service" ];
    wants = [ "redsocks.service" ];
    wantedBy = [ "transparent-proxy.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.nftables}/bin/nft -f - <<'NFT'
      table inet transparent-proxy {
          chain output {
              type nat hook output priority 0;
              ip daddr 127.0.0.0/8 return
              ip daddr 10.0.0.0/8 return
              ip daddr 172.16.0.0/12 return
              ip daddr 192.168.0.0/16 return
              meta skuid != 0 return
              tcp dport 1-65535 redirect to :12345
          }
      }
      NFT
    '';
    preStop = ''
      ${pkgs.nftables}/bin/nft delete table inet transparent-proxy 2>/dev/null || true
    '';
  };

  # Toggle target — systemctl start/stop to enable/disable transparent proxy
  systemd.targets.transparent-proxy = {
    description = "Transparent proxy via nftables + redsocks → Xray SOCKS5";
    after = [
      "network-online.target"
      "xray.service"
    ];
    wants = [
      "network-online.target"
      "redsocks.service"
      "transparent-proxy-rules.service"
    ];
  };

  # Convenience script: rebuild-proxied — toggle proxy on, rebuild, toggle off.
  # Uses trap so proxy is torn down even if the build fails or is interrupted.
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "rebuild-proxied" ''
      set -euo pipefail
      cleanup() {
        echo "[rebuild-proxied] stopping transparent proxy..."
        ${pkgs.systemd}/bin/systemctl stop transparent-proxy.target 2>/dev/null || true
        echo "[rebuild-proxied] done."
      }
      trap cleanup EXIT
      echo "[rebuild-proxied] starting transparent proxy..."
      ${pkgs.systemd}/bin/systemctl start transparent-proxy.target
      echo "[rebuild-proxied] running nixos-rebuild..."
      ${config.system.build.nixos-rebuild}/bin/nixos-rebuild "$@"
    '')
    (pkgs.writeShellScriptBin "nh-proxied" ''
      set -euo pipefail
      cleanup() {
        echo "[nh-proxied] stopping transparent proxy..."
        ${pkgs.systemd}/bin/systemctl stop transparent-proxy.target 2>/dev/null || true
        echo "[nh-proxied] done."
      }
      trap cleanup EXIT
      echo "[nh-proxied] starting transparent proxy..."
      ${pkgs.systemd}/bin/systemctl start transparent-proxy.target
      echo "[nh-proxied] running nh..."
      ${pkgs.nh}/bin/nh "$@"
    '')
  ];
}
