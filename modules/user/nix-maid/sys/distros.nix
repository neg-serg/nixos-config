{
  pkgs,
  lib,
  ...
}:
lib.mkIf true {
  # Distrobox
  environment.systemPackages = [ pkgs.distrobox ]; # Container wrapper for running any Linux distribution in your terminal
}
