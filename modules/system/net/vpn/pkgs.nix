{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    amnezia-vpn # Amnezia VPN client
    amneziawg-go # userspace Go implementation of AmneziaWG
    amneziawg-tools # tools for configuring AmneziaWG
    netbird # WireGuard-based mesh network with SSO/MFA
    openconnect # Cisco AnyConnect (open source)
    wireguard-tools # tools for the WireGuard secure network tunnel
    (openvpn.override {
      pkcs11Support = true;
      inherit (pkgs) pkcs11helper;
    }) # OpenVPN with PKCS#11 support
    update-resolv-conf # apply pushed DNS options to resolv.conf
  ];
}
