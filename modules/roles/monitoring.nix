##
# Module: roles/monitoring
# Purpose: Lightweight monitoring role for workstations/gaming.
# Key options: cfg = config.roles.monitoring.enable
# Behavior when enabled:
#  - Enable sysstat collectors (ultra-low overhead)
#  - Enable Netdata with conservative settings and local-only bind
#  - Enable atop (CLI/system activity reporter)
{
  lib,
  config,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf mkDefault;
  cfg = config.roles.monitoring;
in
{
  options.roles.monitoring.enable = mkEnableOption "Enable lightweight monitoring role.";

  config = mkIf cfg.enable {
    # Ultra-light historical collectors
    monitoring.sysstat.enable = mkDefault true;


    # CLI system activity tools are provided via environment.systemPackages
    # (No upstream NixOS service option for atop in this channel)
  };
}
