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
        networkConfig.DHCP = "ipv4";
        dhcpV4Config = {
          UseDNS = true;
          UseRoutes = true;
          RouteMetric = 50; # prefer net1 (10G) over net0 (1G)
        };
      };
      "11-lan" = {
        matchConfig.Name = "net1";
        networkConfig.DHCP = "ipv4";
        dhcpV4Config = {
          UseDNS = true;
          UseRoutes = true;
          RouteMetric = 10; # lowest metric wins → default route via 10G
        };
      };
    };
  };
}
