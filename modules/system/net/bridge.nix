##
# Module: system/net/bridge
# Purpose: Optional host-local bridge (br0) with DHCP server.
# Key options: cfg = config.profiles.network.bridge.enable
# Dependencies: systemd-networkd; adds firewall allowance for DHCP.
{
  lib,
  config,
  ...
}:
let
  cfg = config.profiles.network.bridge or { enable = false; };
in
{
  options.profiles.network.bridge.enable =
    lib.mkEnableOption "Enable local bridge br0 with DHCP server";

  config = lib.mkIf cfg.enable {
    systemd.network = {
      netdevs."br0".netdevConfig = {
        Kind = "bridge";
        Name = "br0";
      };
      networks."10-br0" = {
        matchConfig.Name = "br0";
        address = [ "192.168.122.1/24" ];
        # Local bridge for VMs, don't wait for it
        linkConfig.RequiredForOnline = "no";
        networkConfig.DHCPServer = "yes";
        dhcpServerConfig = {
          PoolOffset = 50;
          PoolSize = 101;
          EmitDNS = true;
          DNS = [ "192.168.122.1" ];
          EmitRouter = true;
          Router = "192.168.122.1";
          DefaultLeaseTimeSec = 12 * 3600;
          MaxLeaseTimeSec = 24 * 3600;
        };
      };
    };

    # Allow DHCP server traffic on br0
    networking.firewall.interfaces.br0.allowedUDPPorts = [
      67
      68
    ];
  };
}
