{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.amnezia-vpn # Amnezia VPN client
    pkgs.amneziawg-go # userspace Go implementation of AmneziaWG
    pkgs.amneziawg-tools # tools for configuring AmneziaWG
    pkgs.netbird # WireGuard-based mesh network with SSO/MFA
    pkgs.throne # Qt GUI proxy configuration manager (sing-box client)
    pkgs.openconnect # Cisco AnyConnect (open source)
    pkgs.wireguard-tools # tools for the WireGuard secure network tunnel
    (pkgs.openvpn.override { # Robust and highly flexible tunneling application
      # Robust and highly flexible tunneling application
      pkcs11Support = true;
      inherit (pkgs) pkcs11helper;
    }) # OpenVPN with PKCS#11 support
    pkgs.update-resolv-conf # apply pushed DNS options to resolv.conf
  ];
}
