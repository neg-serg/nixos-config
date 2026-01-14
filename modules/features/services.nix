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
      tws.enable = mkBool "enable Trader Workstation (IBKR) desktop client" false;
    };

    net = {
      tailscale.enable = mkBool "enable Tailscale mesh VPN and Tailray GUI" false;
      wifi.enable = mkBool "enable Wi-Fi stack and management tools (iwd, wavemon, etc.)" false;
    };

    hardware = {
      amdgpu.rocm.enable = mkBool "enable AMDGPU ROCm support" false;
    };
  };
}
