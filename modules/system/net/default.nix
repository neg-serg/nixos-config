{ ... }:
{
  imports = [
    ./bridge.nix
    ./nscd.nix
    ./pkgs.nix
    ./proxy.nix
    ./ssh.nix
    ./wifi.nix
    ./vpn
  ];
}
