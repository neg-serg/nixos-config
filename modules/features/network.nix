{ lib, mkBool, ... }:
with lib;
{
  options.features = {
    mail = {
      enable = mkBool "enable Mail stack (notmuch, isync, vdirsyncer, etc.)" true;
      vdirsyncer.enable = mkBool "enable Vdirsyncer sync service/timer" true;
      mbsync.enable = mkBool "enable mbsync IMAP sync service/timer" true;
    };

    # Torrent stack (Transmission and related tools/services)
    torrent = {
      enable = mkBool "enable Torrent stack (Transmission, tools, services)" true;
    };

    net = {
      tailscale.enable = mkBool "enable Tailscale mesh VPN and Tailray GUI" false;
      wifi.enable = mkBool "enable Wi-Fi stack and management tools (iwd, wavemon, etc.)" false;
      proxy.enable = mkBool "enable Xray SOCKS5 proxy (127.0.0.1:10808)" false;
      zapret2.enable = mkBool "enable Zapret2 DPI bypass via nfqueue (requires zapret2 package)" false;
      rknDomains.enable = mkBool "enable RKN domain blocklist fetcher with daily timer" false;
      netHealth.enable = mkBool "enable periodic network/DNS/zapret2 health check with self-heal and ntfy push" false;
      bbrv3.enable = mkBool "enable TCP BBRv3 congestion control (kernel >= 6.18)" true;
    };

    hardware = {
      amdgpu.rocm.enable = mkBool "enable AMDGPU ROCm support" false;
    };

  };
}
