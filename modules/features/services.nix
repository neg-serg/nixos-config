{ lib, ... }:
with lib;
let
  mkBool = desc: default: (lib.mkEnableOption desc) // { inherit default; };
in
{
  options.features = {
    mail = {
      enable = mkBool "enable Mail stack (notmuch, isync, vdirsyncer, etc.)" true;
      vdirsyncer.enable = mkBool "enable Vdirsyncer sync service/timer" true;
    };

    # Torrent stack (Transmission and related tools/services)
    torrent = {
      enable = mkBool "enable Torrent stack (Transmission, tools, services)" true;
      prometheus.enable = mkBool "enable Prometheus exporter for Transmission (transmission-exporter)" false;
    };

    finance = {

    };

    net = {
      tailscale.enable = mkBool "enable Tailscale mesh VPN and Tailray GUI" false;
      wifi.enable = mkBool "enable Wi-Fi stack and management tools (iwd, wavemon, etc.)" false;
      proxy.enable = mkBool "enable Xray SOCKS5 proxy (127.0.0.1:10808)" false;
      lan-proxy.enable = mkBool "enable LAN SOCKS5 proxy without auth (0.0.0.0:10809)" false;
      transparent-proxy.enable = mkBool "enable transparent proxy (nftables + redsocks -> Xray SOCKS5)" false;
      transparent-tun.enable = mkBool "enable TUN-based routing for nix traffic (nftables fwmark → custom routing table)" false;
      vpn-scripts.enable = mkBool "enable VPN helper scripts collection (zen-vpn, cdn-proxy, split-router, etc.)" false;
      awgTunnel.enable = mkBool "enable AmneziaWG obfuscated WireGuard tunnel (requires amneziawg-dkms)" false;
      zapret2.enable = mkBool "enable Zapret2 DPI bypass via nfqueue (requires zapret2 package)" false;
      rknDomains.enable = mkBool "enable RKN domain blocklist fetcher with daily timer" false;
    };

    hardware = {
      amdgpu.rocm.enable = mkBool "enable AMDGPU ROCm support" false;
    };
  };
}
