{
  config,
  lib,
  pkgs,
  ...
}:
let
  onDemand = config.lib.neg.onDemand pkgs;
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
  ];
  # Throne (features.apps.throne): optional Qt GUI for proxy profile editing,
  # nothing more. `programs.throne` is the nixpkgs module — it installs the
  # package and, only with tunMode, the capability wrapper the core needs to
  # open a TUN device. It ships no unit and no autostart, so a disabled flag
  # costs nothing and an enabled one stays inert until started by hand.
  programs.throne = lib.mkIf (config.lib.neg.enabled "apps.throne") {
    enable = true;
    tunMode.enable = config.lib.neg.enabled "apps.throne.tunMode";
  };
}
