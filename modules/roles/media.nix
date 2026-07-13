##
# Module: roles/media
# Purpose: Media role (MPD etc).
# Key options: cfg = config.roles.media.enable
# Dependencies: Enables profiles.services.* (mpd, avahi, openssh).
{
  lib,
  config,
  ...
}:
let
  cfg = config.roles.media;
in
{
  options.roles.media.enable = lib.mkEnableOption "Enable media role (media servers and discovery).";

  config = lib.mkIf cfg.enable {
    profiles.services = {
      mpd.enable = lib.mkDefault true;
      avahi.enable = lib.mkDefault true;
      openssh.enable = lib.mkDefault true;
    };
  };
}
