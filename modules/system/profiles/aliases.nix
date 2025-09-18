##
# Module: system/profiles/aliases
# Purpose: Alias profiles.services.* → servicesProfiles.* for unified naming.
# Key options: none (option redirection only).
# Dependencies: lib.mkAliasOptionModule; affects modules referencing profiles.services.*
{lib, ...}: let
  mk = svc: lib.mkAliasOptionModule ["profiles" "services" svc "enable"] ["servicesProfiles" svc "enable"];
  # Optional extra alias for service-specific options
  mkExtra = lib.mkAliasOptionModule ["profiles" "services" "adguardhome" "rewrites"] ["servicesProfiles" "adguardhome" "rewrites"];
  services = [
    "adguardhome"
    "unbound"
    "openssh"
    "syncthing"
    "mpd"
    "navidrome"
    "wakapi"
    "nextcloud"
    "avahi"
    "jellyfin"
    "samba"
  ];
in {
  imports = (map mk services) ++ [mkExtra];
}
