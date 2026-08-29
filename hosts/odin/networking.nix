{ config, ... }: {
  networking = {
    hostName = "odin";
    hostId = config.networking.hostName |> builtins.hashString "sha1" |> builtins.substring 0 8; # Required for ZFS pool import
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

  # No global IPv6 upstream: Steam/other apps pick AAAA from DNS and stall
  # (no Happy-Eyeballs fallback). Keep IPv6 off on the physical uplink only;
  # tailscale0 (fd7a:) keeps its IPv6 for the tailnet.
  boot.kernel.sysctl."net.ipv6.conf.net1.disable_ipv6" = 1;

  # Enable local bridge (br0) with DHCP server
  profiles.network.bridge.enable = true;

  systemd.network = {
    networks = {
      "10-lan-v2" = {
        matchConfig.Name = "net0";
        # BPI R4 Pro (new router): DHCP from its LAN (192.168.1.x); the
        # static fallback keeps access to 192.168.1.1 even before DHCP is up.
        networkConfig.DHCP = "ipv4";
        # Keep system DNS (local unbound) — don't take DNS from the BPI yet
        dhcpV4Config.UseDNS = false;
        # Legacy MikroTik fallbacks, kept until the BPI migration is done
        address = [
          "192.168.1.50/24"
          "10.0.2.140/27"
          "192.168.88.140/24"
        ];
        # Don't block boot waiting for net0
        linkConfig.RequiredForOnline = "no";
      };
      "11-lan" = {
        matchConfig.Name = "net1";
        networkConfig = {
          # Static LAN address (previously DHCP): stable for the phone remote
          # panel — dsh-lan-proxy binds 192.168.2.87:3080 — and for br0 NAT.
          # Keep .87 out of the router's DHCP pool (reserve it) to avoid a
          # duplicate-address conflict.
          # Alias .88: the dockur Windows VM's DHCP lease collides with the
          # host's .87, so the VM reaches the host's sing-box through this
          # alias (auth-less in-lan-vm inbound, port 10811, LAN-only).
          Address = [
            "192.168.2.87/24"
            "192.168.2.88/24"
          ];
          KeepConfiguration = "yes";
        };
        # Default route via the router, same metric the DHCP lease used
        # (lowest wins → default route via 10G).
        routes = [
          {
            Destination = "0.0.0.0/0";
            Gateway = "192.168.2.1";
            Metric = 10;
          }
        ];
        # net1 is optional (e.g. unplugged 10G), don't wait for it
        linkConfig = {
          RequiredForOnline = "no";
          ActivationPolicy = "always-up";
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
