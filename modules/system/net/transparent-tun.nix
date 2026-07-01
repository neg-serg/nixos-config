{
  pkgs,
  lib,
  config,
  ...
}:
# TUN-based routing for nix-daemon downloads.
#
# No VPN config changes required — the module temporarily moves the VPN's
# default route from the main table into a custom table, then uses nftables
# fwmark + ip rule to route only nix traffic through it.
#
# ── Usage ──
#   nh-tun os switch /etc/nixos   # rebuild through TUN, auto-cleanup
let
  cfg = config.features.net.transparent-tun or { };
  tunTable = 100;
  tunMark = 1;
in
lib.mkIf cfg.enable {
  systemd.services.transparent-tun-setup = {
    description = "Move TUN default route to custom table for nix-only routing";
    wantedBy = [ "transparent-tun.target" ];
    before = [ "transparent-tun.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.iproute2 pkgs.gawk ];
    script = ''
      # Find the TUN interface (awg, tun, wg — anything with a default route)
      TUN_IFACE=""
      for iface in $(ip -o link show | awk -F': ' '/awg|tun|wg/{print $2}'); do
        if ip route show dev "$iface" 2>/dev/null | grep -qE '^default|^0\.0\.0\.0/0|^0\.0\.0\.0/1'; then
          TUN_IFACE="$iface"
          break
        fi
      done

      if [ -z "$TUN_IFACE" ]; then
        echo "transparent-tun: no TUN interface with default route found" >&2
        exit 1
      fi

      echo "transparent-tun: using $TUN_IFACE → moving default route to table ${toString tunTable}"

      # Move ALL default/0.0.0.0 routes from main to our custom table.
      # wg-quick uses 0.0.0.0/1 + 128.0.0.0/1 (two /1 routes instead of /0).
      ip route show dev "$TUN_IFACE" | while read -r route; do
        ip route del $route dev "$TUN_IFACE" 2>/dev/null || true
        ip route add $route dev "$TUN_IFACE" table ${toString tunTable} 2>/dev/null || true
      done

      # Ensure fwmark → table mapping
      ip rule add fwmark ${toString tunMark} table ${toString tunTable} 2>/dev/null || true

      # nftables: mark root outbound TCP to external hosts
      nft -f - <<'NFT'
      table inet transparent-tun {
          chain output {
              type route hook output priority 0;
              ip daddr 127.0.0.0/8 return
              ip daddr 10.0.0.0/8 return
              ip daddr 172.16.0.0/12 return
              ip daddr 192.168.0.0/16 return
              meta skuid 0 tcp dport { 443, 80 } mark set ${toString tunMark}
          }
      }
      NFT

      echo "transparent-tun: ready"
    '';
    preStop = ''
      # Restore routes to main table
      for iface in $(ip -o link show | awk -F': ' '/awg|tun|wg/{print $2}'); do
        ip route show table ${toString tunTable} dev "$iface" 2>/dev/null | while read -r route; do
          ip route add $route dev "$iface" 2>/dev/null || true
          ip route del $route dev "$iface" table ${toString tunTable} 2>/dev/null || true
        done
      done

      ip rule del fwmark ${toString tunMark} table ${toString tunTable} 2>/dev/null || true
      nft delete table inet transparent-tun 2>/dev/null || true
      echo "transparent-tun: routes restored to main table"
    '';
  };

  systemd.targets.transparent-tun = {
    description = "TUN-based routing for nix traffic (table ${toString tunTable})";
    wants = [ "transparent-tun-setup.service" ];
    after = [
      "network-online.target"
      "transparent-tun-setup.service"
    ];
  };

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "nh-tun" ''
      set -euo pipefail
      cleanup() {
        echo "[nh-tun] cleaning up..."
        ${pkgs.systemd}/bin/systemctl stop transparent-tun.target 2>/dev/null || true
        echo "[nh-tun] routing restored."
      }
      trap cleanup EXIT
      echo "[nh-tun] enabling TUN routing for nix..."
      ${pkgs.systemd}/bin/systemctl start transparent-tun.target
      echo "[nh-tun] running nh..."
      ${pkgs.nh}/bin/nh "$@"
    '')
  ];
}
