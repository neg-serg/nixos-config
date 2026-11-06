{
  config,
  lib,
  pkgs,
  ...
}:
let
  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") {
    inherit pkgs;
    nix = config.nix.package;
  };
in
{
  environment.systemPackages = [
    # Qt GUI client for one-off profile edits; the actual tunnel daemons below
    # (amneziawg-go, wireguard-tools, sing-box) stay installed.
    (onDemand {
      name = "amnezia-vpn";
      attr = "amnezia-vpn";
      binary = "AmneziaVPN";
    })
    (pkgs.makeDesktopItem {
      name = "amnezia-vpn";
      desktopName = "Amnezia VPN";
      genericName = "VPN client";
      comment = "Amnezia VPN client (built on first launch)";
      exec = "amnezia-vpn %U";
      icon = "amnezia-vpn";
      categories = [
        "Network"
        "Security"
      ];
    })
    pkgs.amneziawg-go # userspace Go implementation of AmneziaWG
    pkgs.amneziawg-tools # tools for configuring AmneziaWG
    pkgs.wireguard-tools # tools for the WireGuard secure network tunnel
    pkgs.update-resolv-conf # apply pushed DNS options to resolv.conf
    pkgs.sing-box # universal proxy platform
  ]
  ++ lib.optional (config.lib.neg.enabled "apps.throne") pkgs.throne;
}
