##
# Module: servers/avahi
# Purpose: Avahi (mDNS) profile for local discovery.
# Key options: cfg = config.servicesProfiles.avahi.enable
# Dependencies: services.avahi.
{
  lib,
  config,
  ...
}:
let
  cfg = config.servicesProfiles.avahi or { enable = false; };
in
{
  config = lib.mkIf cfg.enable {
    services.avahi = {
      enable = true;
      nssmdns4 = true; # Needed for mDNS (IPv4)
      nssmdns6 = true; # Enable mDNS for IPv6
      openFirewall = true;
      publish = {
        enable = true;
        userServices = true;
        workstation = true;
      };
    };
  };
}
