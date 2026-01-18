{
  config,
  lib,
  pkgs,
  ...
}:
{
  environment.systemPackages = [
    pkgs.amnezia-vpn # Amnezia VPN client
    pkgs.amneziawg-go # userspace Go implementation of AmneziaWG
    pkgs.amneziawg-tools # tools for configuring AmneziaWG
    pkgs.wireguard-tools # tools for the WireGuard secure network tunnel
    (pkgs.openvpn.override {
      # Robust and highly flexible tunneling application
      pkcs11Support = true;
      inherit (pkgs) pkcs11helper;
    }) # OpenVPN with PKCS#11 support
    pkgs.update-resolv-conf # apply pushed DNS options to resolv.conf
  ]
  ++ lib.optional (config.features.apps.throne.enable or false) pkgs.throne;
}
