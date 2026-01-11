{
  lib,
  config,
  ...
}:
let
  cfg = config.servicesProfiles.jellyfin or { enable = false; };
in
{
  config = lib.mkIf cfg.enable {
    services.jellyfin = {
      enable = true;
      openFirewall = false;
    };
  };
}
