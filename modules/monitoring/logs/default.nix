##
# Module: monitoring/logs
# Purpose: Umbrella toggle to enable Loki + Promtail together.
# Key options: monitoring.logs.enable
{
  lib,
  config,
  ...
}: let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.monitoring.logs or {};
in {
  options.monitoring.logs.enable =
    mkEnableOption "Enable logs stack (Loki + Promtail).";

  config = mkIf (cfg.enable or false) {
    monitoring.loki.enable = true;
    monitoring.promtail.enable = true;
  };
}
