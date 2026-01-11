##
# Module: servers/gns3
# Purpose: GNS3 network simulation server with Cisco/Dynamips emulation.
# Key options: cfg = config.servicesProfiles.gns3.enable
# Dependencies: Requires gns3-gui package for graphical interface.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.servicesProfiles.gns3 or { enable = false; };
in
{
  config = lib.mkIf cfg.enable {
    services.gns3-server = {
      enable = true;
      dynamips.enable = true; # Cisco IOS router emulation
      ubridge.enable = true; # bridge virtual and real network interfaces
      vpcs.enable = true; # Virtual PC Simulator for lightweight hosts
    };

    # GNS3 GUI client
    environment.systemPackages = [
      pkgs.gns3-gui # graphical network topology designer
    ];
  };
}
