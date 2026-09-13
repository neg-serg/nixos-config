{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:
lib.mkIf (builtins.pathExists (inputs.self + "/secrets/odin-wireguard-wg-quick.sops")) {
  # On-demand WireGuard VPN for odin, configured via wg-quick config stored in sops.
  # The tunnel is not started automatically; use systemctl start/stop to control it.
  sops.secrets."wireguard/odin-wg-quick" = {
    sopsFile = inputs.self + "/secrets/odin-wireguard-wg-quick.sops";
    format = "binary"; # keep original wg-quick config format
    owner = "root";
    group = "root";
    mode = "0600";
  };

  systemd.services."wg-quick-vpn-odin" = {
    description = "On-demand WireGuard VPN (odin, wg-quick)";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    wantedBy = [ ]; # do not autostart; manual systemctl only
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${lib.getExe' pkgs.wireguard-tools "wg-quick"} up ${
        # Tools for the WireGuard secure network tunnel
        config.sops.secrets."wireguard/odin-wg-quick".path
      }";
      ExecStop = "${lib.getExe' pkgs.wireguard-tools "wg-quick"} down ${
        # Tools for the WireGuard secure network tunnel
        config.sops.secrets."wireguard/odin-wg-quick".path
      }";
    };
  };
}
