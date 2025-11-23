##
# Module: roles/homelab
# Purpose: Homelab role (self-hosting defaults).
# Key options: cfg = config.roles.homelab.enable
# Dependencies: Enables profiles.security and profiles.services.* (adguardhome, unbound, openssh, mpd, navidrome, wakapi, nextcloud).
{
  lib,
  config,
  ...
}: let
  cfg = config.roles.homelab;
in {
  options.roles.homelab.enable = lib.mkEnableOption "Enable homelab role (self-hosting services).";

  config = lib.mkIf cfg.enable {
    # Homelab defaults: prioritize security profile; performance stays opt-in per host.
    profiles.security.enable = lib.mkDefault true;

    # Core self-hosted services commonly used in homelab.
    profiles.services = {
      adguardhome.enable = lib.mkDefault true;
      unbound.enable = lib.mkDefault true;
      openssh.enable = lib.mkDefault true;
      mpd.enable = lib.mkDefault true;
      navidrome.enable = lib.mkDefault true;
      wakapi.enable = lib.mkDefault true;
      nextcloud.enable = lib.mkDefault true;
    };
  };
}
