{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.throne # Qt-based cross-platform GUI proxy configuration manager
  ];
}
