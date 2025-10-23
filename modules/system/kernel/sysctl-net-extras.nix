##
# Module: system/kernel/sysctl-net-extras
# Purpose: Optional, moderate network sysctl tweaks for desktop/workstation.
# Key options: profiles.performance.netExtras.* (all disabled by default)
# Dependencies: Applies to boot.kernel.sysctl.
{ lib, config, ... }:
let
  opts = import ../../../lib/opts.nix { inherit lib; };
  cfg = config.profiles.performance.netExtras;
in {
  options.profiles.performance.netExtras = {
    enable = opts.mkEnableOption "Enable optional network sysctl tweaks (moderate).";

    # Reuse TIME_WAIT sockets for outgoing connections (clients). Harmless for
    # most desktop workflows. Keep off by default; enable if you open many short
    # TCP connections (browsers, package managers, etc.).
    tcpTwReuse = {
      enable = opts.mkBoolOpt {
        default = false;
        description = "Enable net.ipv4.tcp_tw_reuse=1 to moderately speed up TIME_WAIT reuse for clients.";
      };
    };

    # Reduce FIN-WAIT timeout to free sockets slightly faster on busy clients.
    # Default kernel is 60s; 30s is a common conservative choice.
    tcpFinTimeout = {
      enable = opts.mkBoolOpt {
        default = false;
        description = "Enable net.ipv4.tcp_fin_timeout with a reduced timeout for faster socket cleanup.";
      };
      value = opts.mkIntOpt {
        default = 30;
        description = "Value for net.ipv4.tcp_fin_timeout (seconds).";
        example = 30;
      };
    };
  };

  config = lib.mkIf (cfg.enable or false) (
    lib.mkMerge [
      (lib.mkIf (cfg.tcpTwReuse.enable or false) {
        boot.kernel.sysctl."net.ipv4.tcp_tw_reuse" = 1;
      })
      (lib.mkIf (cfg.tcpFinTimeout.enable or false) {
        boot.kernel.sysctl."net.ipv4.tcp_fin_timeout" = cfg.tcpFinTimeout.value;
      })
    ]
  );
}

