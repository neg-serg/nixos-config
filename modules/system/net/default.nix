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
    ./vpn
  ];
}
