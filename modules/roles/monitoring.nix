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

    # Netdata: local UI, minimized overhead for gaming
    monitoring.netdata.enable = mkDefault true;
    services.netdata = {
      enableAnalyticsReporting = false;
      # Keep python plugins off by default to save CPU/mem
      python.enable = false;
      # Minimal netdata.conf
      config = {
        global = {
          # less frequent updates reduce overhead while keeping responsiveness
          "update every" = 2;
          # store in RAM to avoid disk I/O during gaming
          "memory mode" = "ram";
        };
        web = {
          # bind locally
          "bind to" = "127.0.0.1";
        };
        plugins = {
          # disable heavy collectors by default on a gaming PC
          apps = "no";
          ebpf = "no";
          # leave go.d enabled (lightweight); python.d disabled via python.enable = false
        };
      };
    };

    # CLI system activity tools are provided via environment.systemPackages
    # (No upstream NixOS service option for atop in this channel)
  };
}
