_: {
  networking = {
    hostName = "odin";
    hostId = "ab0cd1ef"; # Required for ZFS pool import
    hosts."10.0.2.140" = [
      "odin"
      "odin.local"
    ];

    # NAT from the local bridge (br0, 192.168.122.0/24) to the main uplink
    # so VMs/LXC containers on br0 have Internet access.
    nat = {
      enable = true;
      externalInterface = "net1";
      internalInterfaces = [ "br0" ];
    };

    # Use systemd-networkd for networking
    useNetworkd = true;
    useDHCP = false;
  };

  # Enable local bridge (br0) with DHCP server
  profiles.network.bridge.enable = true;
  # Allow Wi-Fi management via reusable feature switch
  features.net.wifi.enable = false;

  systemd.network = {
    networks = {
      "10-lan-v2" = {
        matchConfig.Name = "net0";
        # Try DHCP first to discover MikroTik's network
        networkConfig.DHCP = "ipv4";
        # Fallback: common MikroTik subnets if DHCP fails
        address = [
          "10.0.2.140/27"
          "192.168.88.140/24"
        ];
        # Don't block boot waiting for net0 (MikroTik may boot later)
        linkConfig.RequiredForOnline = "no";
      };
      "11-lan" = {
        matchConfig.Name = "net1";
        networkConfig.DHCP = "ipv4";
        # net1 is optional (e.g. unplugged 10G), don't wait for it
        linkConfig.RequiredForOnline = "no";
        dhcpV4Config = {
          UseDNS = true;
          UseRoutes = true;
          RouteMetric = 10; # lowest metric wins → default route via 10G
        };
      };
    };
    wait-online = {
      enable = false; # Don't block boot waiting for network
      anyInterface = true; # (kept for reference if re-enabled)
    };
  };

  # Explicitly disable rfkill management as it is not needed and causes delays/issues
  systemd.services."systemd-rfkill".enable = false;
  systemd.sockets."systemd-rfkill".enable = false;

  # Ensure all wireless stacks are force-disabled
  networking.wireless.enable = false; # wpa_supplicant
  networking.wireless.iwd.enable = false; # iwd

}
