##
# Module: roles/workstation
# Purpose: Workstation role (desktop defaults).
# Key options: cfg = config.roles.workstation.enable
# Dependencies: Enables profiles.performance, profiles.services.* (openssh, avahi), kdeconnect.
{
  lib,
  config,
  ...
}: let
  cfg = config.roles.workstation;
in {
  options.roles.workstation.enable = lib.mkEnableOption "Enable workstation role (desktop-first defaults).";

  config = lib.mkIf cfg.enable {
    # Favor performance on a desktop, but allow host overrides.
    profiles.performance.enable = lib.mkDefault true;

    # Common desktop-friendly services.
    profiles.services = {
      openssh.enable = lib.mkDefault true;
      avahi.enable = lib.mkDefault true;
    };

    # Desktop integrations
    programs.kdeconnect.enable = lib.mkDefault true;
  };
}
