{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.xorg.xhost # Manage X server access from nekoray UI
    pkgs.throne # GUI client for Xray/V2Ray cores
  ];
}
