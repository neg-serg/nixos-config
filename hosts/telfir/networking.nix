_: {
  networking = {
    hostName = "telfir";
    hosts."192.168.2.240" = ["telfir" "telfir.local"];
  };

  # Enable local bridge (br0) with DHCP server
  profiles.network.bridge.enable = true;

  systemd.network = {
    networks = {
      "10-lan" = {
        matchConfig.Name = "net0";
        networkConfig.DHCP = "ipv4";
        dhcpV4Config.UseDNS = true;
        dhcpV4Config.UseRoutes = true;
        dhcpV4Config.RouteMetric = 50; # prefer net1 (10G) over net0 (1G)
      };
      "11-lan" = {
        matchConfig.Name = "net1";
        networkConfig.DHCP = "ipv4";
        dhcpV4Config.UseDNS = true;
        dhcpV4Config.UseRoutes = true;
        dhcpV4Config.RouteMetric = 10; # lowest metric wins → default route via 10G
      };
    };
  };
}
