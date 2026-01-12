{ ... }:
{
  imports = [
    ./bridge.nix
    ./nscd.nix
    ./pkgs.nix
    ./firewall.nix
    ./proxy.nix
    ./ssh.nix
    ./wifi.nix
    ./vpn
  ];
}
