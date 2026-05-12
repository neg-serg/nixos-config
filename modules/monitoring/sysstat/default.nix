##
# Module: monitoring/sysstat
# Purpose: Enable sysstat (sar/iostat/mpstat) collectors for ultra-light history.
# Key options: monitoring.sysstat.enable
{
  lib,
  config,
  ...
}:
let
  inherit (lib) mkIf mkEnableOption;
  cfg = config.monitoring.sysstat;
in
{
  options.monitoring.sysstat.enable = mkEnableOption "Enable sysstat collectors (very low overhead).";

  config = mkIf cfg.enable {
    services.sysstat.enable = true;
  };
}
