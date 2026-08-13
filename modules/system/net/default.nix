{ ... }:
{
  imports = [
    ./bridge.nix
    ./nscd.nix
    ./pkgs.nix # Nix package manager
    ./firewall.nix
    ./proxy.nix
    ./ssh.nix
    ./wifi.nix
    ./rkn # Roskomnadzor block bypass
    ./vpn
    ./zapret2 # DPI circumvention
    ./bbrv3.nix # TCP BBRv3 congestion control
  ];
}
