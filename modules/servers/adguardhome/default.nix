##
# Module: servers/adguardhome
# Purpose: AdGuardHome profile + DNS rewrite passthrough.
# Key options: cfg = config.servicesProfiles.adguardhome (enable, rewrites)
# Dependencies: May integrate with Unbound (upstream_dns).
{
  lib,
  config,
  ...
}: let
  cfg =
    config.servicesProfiles.adguardhome or {
      enable = false;
      rewrites = [];
    };
in {
  config = lib.mkIf cfg.enable {
    services.adguardhome = {
      enable = true;
      openFirewall = true;
      # Bind the admin web UI away from :80 so Caddy can use it
      host = "127.0.0.1";
      port = 3000;
      # Make sure our Nix settings are honored strictly to avoid stale state conflicts
      mutableSettings = false;
      settings = {
        dns = {
          # Bind locally and serve on default DNS port.
          bind_host = "127.0.0.1";
          bind_hosts = ["127.0.0.1"]; # restrict to IPv4 localhost to avoid conflicts with libvirt/systemd-resolved
          ipv6 = false;
          port = 53;
          upstream_dns = ["127.0.0.1:5353"];
          bootstrap_dns = ["1.1.1.1" "8.8.8.8"];
          inherit (cfg) rewrites;
        };
      };
    };

    # Make systemd-resolved use AdGuard as upstream.
    networking.nameservers = ["127.0.0.1"];
    services.resolved.domains = ["~."];
  };
}
