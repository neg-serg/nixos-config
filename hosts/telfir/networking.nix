_: {
  networking = {
    hostName = "telfir";
    hosts."192.168.2.240" = [
      "telfir"
      "telfir.local"
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
      "10-lan" = {
        matchConfig.Name = "net0";
        # Static IP configuration (faster boot, no DHCP wait)
        address = [ "192.168.2.240/24" ];
        gateway = [ "192.168.2.1" ];
        dns = [ "192.168.2.1" ];
        # net0 is our main link, we want to wait for it
        linkConfig.RequiredForOnline = "routable";
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
      enable = false;       # Don't block boot waiting for network
      anyInterface = true;  # (kept for reference if re-enabled)
    };
  };
}
