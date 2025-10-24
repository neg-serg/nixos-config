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

    # Congestion control selection (e.g., bbr, cubic). Disabled by default
    # to avoid overriding the base unless explicitly requested.
    congestionControl = {
      enable = opts.mkBoolOpt {
        default = false;
        description = "Set net.ipv4.tcp_congestion_control (e.g., bbr, cubic).";
      };
      algorithm = opts.mkStrOpt {
        default = "bbr";
        description = "Congestion control algorithm string (kernel must support it).";
        example = "bbr";
      };
    };

    # Default qdisc selection (commonly 'fq' with BBR). Disabled by default.
    defaultQdisc = {
      enable = opts.mkBoolOpt {
        default = false;
        description = "Set net.core.default_qdisc (e.g., fq).";
      };
      value = opts.mkStrOpt {
        default = "fq";
        description = "Default queuing discipline value for net.core.default_qdisc.";
        example = "fq";
      };
    };

    # Increase SYN backlog for busy client workloads.
    maxSynBacklog = {
      enable = opts.mkBoolOpt {
        default = false;
        description = "Set net.ipv4.tcp_max_syn_backlog for higher connection rates.";
      };
      value = opts.mkIntOpt {
        default = 8192;
        description = "Value for net.ipv4.tcp_max_syn_backlog.";
        example = 8192;
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
      (lib.mkIf (cfg.congestionControl.enable or false) {
        boot.kernel.sysctl."net.ipv4.tcp_congestion_control" = cfg.congestionControl.algorithm;
      })
      (lib.mkIf (cfg.defaultQdisc.enable or false) {
        boot.kernel.sysctl."net.core.default_qdisc" = cfg.defaultQdisc.value;
      })
      (lib.mkIf (cfg.maxSynBacklog.enable or false) {
        boot.kernel.sysctl."net.ipv4.tcp_max_syn_backlog" = cfg.maxSynBacklog.value;
      })
    ]
  );
}
