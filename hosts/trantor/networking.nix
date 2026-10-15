{ config, lib, ... }: {
  networking = {
    hostName = "trantor";
    hostId = config.networking.hostName |> builtins.hashString "sha1" |> builtins.substring 0 8; # Required for ZFS pool import
    hosts."10.0.2.140" = [
      "trantor"
      "trantor.local"
    ];

    # NAT from the local bridge (br0, 192.168.122.0/24) to the main uplink
    # so VMs on br0 have Internet access.
    nat = {
      enable = true;
      externalInterface = "net1";
      internalInterfaces = [ "br0" ];
    };

    # Use systemd-networkd for networking
    useNetworkd = true;
    useDHCP = false;
  };

  # nat.nix stages an nf_nat_ftp modprobe on every NAT-enabled host; the FTP
  # conntrack helpers were trimmed from the kernel (overlay.config H19j), so
  # drop the stale request — otherwise systemd-modules-load fails at boot.
  boot.kernelModules.nf_nat_ftp = lib.mkForce false;

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
        # Second NIC: plain DHCP on whichever LAN it is plugged into (the
        # legacy 192.168.1.50 / 10.0.2.140 / 192.168.88.140 fallbacks are gone
        # with the old MikroTik addressing).
        networkConfig.DHCP = "ipv4";
        # Keep system DNS (local unbound) — don't take DNS from the router yet
        dhcpV4Config.UseDNS = false;
        # Don't block boot waiting for net0
        linkConfig.RequiredForOnline = "no";
      };
      "11-lan" = {
        matchConfig.Name = "net1";
        networkConfig = {
          # Static LAN address: stable for the phone remote panel —
          # dsh-lan-proxy binds 192.168.0.10:3080 — and for br0 NAT. Keep .10
          # out of the router's DHCP pool (reserve it) to avoid a
          # duplicate-address conflict.
          # Alias .11: the dockur Windows VM's DHCP lease collides with the
          # host's .10, so the VM reaches the host's sing-box through this
          # alias (auth-less in-lan-vm inbound, port 10811, LAN-only).
          Address = [
            "192.168.0.10/24"
            "192.168.0.11/24"
          ];
          KeepConfiguration = "yes";
        };
        # Default route via the router, same metric the DHCP lease used
        # (lowest wins → default route via 10G).
        routes = [
          {
            Destination = "0.0.0.0/0";
            Gateway = "192.168.0.1";
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
