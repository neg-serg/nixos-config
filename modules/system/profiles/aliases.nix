##
# Module: system/profiles/aliases
# Purpose: Alias profiles.services.* → servicesProfiles.* for unified naming.
# Key options: none (option redirection only).
# Dependencies: lib.mkAliasOptionModule; affects modules referencing profiles.services.*
{lib, ...}: let
  mk = svc: lib.mkAliasOptionModule ["profiles" "services" svc "enable"] ["servicesProfiles" svc "enable"];
  # Optional extra aliases for service-specific options
  mkAdguardRewrites = lib.mkAliasOptionModule ["profiles" "services" "adguardhome" "rewrites"] ["servicesProfiles" "adguardhome" "rewrites"];
  mkNextcloudPackage = lib.mkAliasOptionModule ["profiles" "services" "nextcloud" "package"] ["servicesProfiles" "nextcloud" "package"];
  services = [
    "adguardhome"
    "bitcoind"
    "unbound"
    "openssh"
    "mpd"
    "nextcloud"
    "avahi"
    "jellyfin"
    "samba"
  ];
in {
  imports = (map mk services) ++ [mkAdguardRewrites mkNextcloudPackage];
}
