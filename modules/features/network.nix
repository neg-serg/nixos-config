{ mkBool, ... }:
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
      nixDaemonProxy.enable = mkBool "route nix-daemon fetches (substituters, flake inputs) through the local SOCKS5 proxy" true;
      zapret2.enable = mkBool "enable Zapret2 DPI bypass via nfqueue (requires zapret2 package)" false;
      rknDomains.enable = mkBool "enable RKN domain blocklist fetcher with daily timer" false;
      netHealth.enable = mkBool "enable periodic network/DNS/zapret2 health check with self-heal (notifications only when features.net.ntfy is on)" false;
      # Self-hosted ntfy server (:2586) for LAN push notifications. net-health
      # and rollout-watch only post while this is on; the health check itself
      # keeps running either way.
      ntfy.enable = mkBool "enable the self-hosted ntfy push-notification server (LAN :2586)" false;
      ceno.enable = mkBool "enable Ceno/Ouinet P2P client (censorship-circumvention node, podman container)" false;
      bbrv3.enable = mkBool "enable TCP BBRv3 congestion control (kernel >= 6.18)" true;
    };

    hardware = {
      amdgpu.rocm.enable = mkBool "enable AMDGPU ROCm support" false;
    };

  };
}
