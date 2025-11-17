##
# Module: roles/server
# Purpose: Server role (headless/server defaults).
# Key options: cfg = config.roles.server.enable
# Effects: Enables smartd by default for disk health monitoring.
{
  lib,
  config,
  ...
}: let
  cfg = config.roles.server;
in {
  options.roles.server.enable = lib.mkEnableOption "Enable server role (headless defaults).";

  config = lib.mkIf cfg.enable {
    # Enable SMART monitoring by default on server-class hosts,
    # and apply sane defaults for schedule and polling interval.
    services.smartd = {
      enable = lib.mkDefault true;
      # Full monitoring, automatic offline tests, persist attributes,
      # NVMe temperature thresholds, and periodic self-tests:
      #  - Short test daily at 02:00; long test weekly on Sunday at 04:00
      defaults.monitored = lib.mkDefault "-a -o on -S on -W 5,70,80 -s (S/../.././02|L/../../7/04)";
      # Polling interval for smartd (seconds). Default is ~30 minutes; set to 1 hour.
      extraOptions = lib.mkDefault ["--interval=3600"];
    };
  };
}
