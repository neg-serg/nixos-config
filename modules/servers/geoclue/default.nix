##
# Module: servers/geoclue
# Purpose: Geolocation service using BeaconDB (Mozilla Location Service alternative).
# Key options: cfg = config.servicesProfiles.geoclue.enable
# Dependencies: services.geoclue2
{
  lib,
  config,
  ...
}: let
  cfg = config.servicesProfiles.geoclue or {enable = false;};
in {
  config = lib.mkIf cfg.enable {
    services.geoclue2 = {
      enable = true;
      geoProviderUrl = "https://beacondb.net/v1/geolocate";
      submissionUrl = "https://beacondb.net/v2/geosubmit";
      submissionNick = "geoclue";

      appConfig.gammastep = {
        isAllowed = true;
        isSystem = false;
      };
    };
  };
}
