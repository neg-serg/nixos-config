{ ... }:
{
  imports = [
    ./bridge.nix
    ./nscd.nix
    ./pkgs.nix # Nix package manager
    ./firewall.nix
    ./proxy.nix
    ./lan-proxy.nix
    ./transparent-proxy.nix
    ./transparent-tun.nix
    ./ssh.nix
    ./wifi.nix
    ./vpn
    ./vpn-scripts
  ];
}
