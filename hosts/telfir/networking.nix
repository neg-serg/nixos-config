{pkgs, ...}: {
  networking = {
    hostName = "telfir";
    hosts."192.168.2.240" = ["telfir" "telfir.local"];

    # NAT from the local bridge (br0, 192.168.122.0/24) to the main uplink
    # so VMs/LXC containers on br0 have Internet access.
    nat = {
      enable = true;
      externalInterface = "net1";
      internalInterfaces = ["br0"];
    };
  };

  # Enable local bridge (br0) with DHCP server
  profiles.network.bridge.enable = true;
  # Allow Wi-Fi management via reusable profile switch
  profiles.network.wifi.enable = true;

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

  # Pin link params and disable EEE/powersave on wired NICs
  systemd.services = {
    ethtool-net0 = {
      description = "Set link params for net0 (Realtek 5GbE)";
      after = ["systemd-networkd-wait-online.service"];
      wants = ["systemd-networkd-wait-online.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = let
          script = pkgs.writeShellScript "ethtool-net0" ''
            #!/bin/sh
            set -e
            IF=net0
            [ -e /sys/class/net/$IF ] || exit 0
            ${pkgs.ethtool}/bin/ethtool -s $IF speed 5000 duplex full autoneg on
            ${pkgs.ethtool}/bin/ethtool --set-eee $IF eee off
          '';
        in "${script}";
      };
      wantedBy = ["multi-user.target"];
    };

    ethtool-net1 = {
      description = "Set link params for net1 (Aquantia 10GbE)";
      after = ["systemd-networkd-wait-online.service"];
      wants = ["systemd-networkd-wait-online.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = let
          script = pkgs.writeShellScript "ethtool-net1" ''
            #!/bin/sh
            set -e
            IF=net1
            [ -e /sys/class/net/$IF ] || exit 0
            ${pkgs.ethtool}/bin/ethtool -s $IF speed 10000 duplex full autoneg on
            ${pkgs.ethtool}/bin/ethtool --set-eee $IF eee off
          '';
        in "${script}";
      };
      wantedBy = ["multi-user.target"];
    };
  };
}
