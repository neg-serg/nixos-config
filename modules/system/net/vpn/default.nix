{ ... }:
{
  imports = [
    ./pkgs.nix # Nix package manager

    ./xray.nix
    ./tun.nix
  ];
}
