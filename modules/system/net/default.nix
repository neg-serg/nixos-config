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
    ./rkn # Roskomnadzor block bypass
    ./vpn
    ./vpn-scripts
    ./zapret2 # DPI circumvention
    ./bbrv3.nix # TCP BBRv3 congestion control
  ];
}
