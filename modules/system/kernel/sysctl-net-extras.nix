##
# Module: system/kernel/sysctl-net-extras
# Purpose: Simple, safe network sysctl tweaks for desktop/workstations.
# Behavior: One toggle applies a minimal, moderate preset.
# - net.ipv4.tcp_tw_reuse = 1
# - net.ipv4.tcp_fin_timeout = <finTimeoutSeconds> (default: 30s)
# Dependencies: Applies to boot.kernel.sysctl.
{
  lib,
  config,
  ...
}: let
  opts = import ../../../lib/opts.nix {inherit lib;};
  cfg = config.profiles.performance.netExtras;
in {
  options.profiles.performance.netExtras = {
    enable = opts.mkEnableOption "Enable a minimal preset of moderate network sysctl tweaks for clients.";

    # FIN-WAIT timeout: default kernel is ~60s; 30s is a conservative desktop value.
    finTimeoutSeconds = opts.mkIntOpt {
      default = 30;
      description = "Value for net.ipv4.tcp_fin_timeout (seconds).";
      example = 30;
    };
  };

  config = lib.mkIf (cfg.enable or false) {
    boot.kernel.sysctl = {
      "net.ipv4.tcp_tw_reuse" = 1;
      "net.ipv4.tcp_fin_timeout" = cfg.finTimeoutSeconds;
    };
  };
}
