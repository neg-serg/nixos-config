{ ... }:
{
  imports = [
    ./awg-tunnel.nix
    ./pkgs.nix # Nix package manager

    ./xray.nix
    ./tun.nix
  ];
}
