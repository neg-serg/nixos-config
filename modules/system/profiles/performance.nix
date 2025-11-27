##
# Module: system/profiles/performance
# Purpose: Performance toggles influencing boot.kernelParams and related behavior.
# Key options: cfg = config.profiles.performance.*
# Dependencies: Consumed by kernel/params.nix.
{
  lib,
  inputs,
  ...
}:
# This module defines a feature flag and granular toggles to apply
# performance-oriented kernel/boot tweaks system-wide.
#
# WARNING: These options may reduce security and/or stability.
# Enable only what you need and understand.
let
  opts = import (inputs.self + "/lib/opts.nix") {inherit lib;};
in {
  options.profiles.performance = with opts; {
    enable = mkEnableOption "Performance-oriented kernel/boot tweaks (reduces security; use with care).";

    # Optimize initrd compression (trade build time for smaller image).
    optimizeInitrdCompression = mkBoolOpt {
      default = false;
      description = "Use zstd -19 -T0 for initrd compression (slower builds, smaller initrd).";
    };

    # Granular toggles (all default to true to preserve legacy behavior when
    # profiles.performance.enable = true)
    disableMitigations = mkBoolOpt {
      default = true;
      description = "Add mitigations=off (disables CPU vulnerability mitigations).";
    };
    quietBoot = mkBoolOpt {
      default = false;
      description = "Reduce boot verbosity (quiet, splash, hide systemd status).";
    };
    disableWatchdogs = mkBoolOpt {
      default = true;
      description = "Disable watchdogs (nowatchdog, kernel.nmi_watchdog=0).";
    };
    lowLatencyScheduling = mkBoolOpt {
      default = true;
      description = "Favor latency: preempt=full and threadirqs.";
    };
    fastRCU = mkBoolOpt {
      default = true;
      description = "Faster RCU grace periods: rcupdate.rcu_expedited=1.";
    };
    pciePerformance = mkBoolOpt {
      default = true;
      description = "Prefer PCIe performance: pcie_aspm=performance.";
    };
    trustTSC = mkBoolOpt {
      default = true;
      description = "Trust TSC clocksource: tsc=reliable.";
    };
    skipCryptoSelftests = mkBoolOpt {
      default = true;
      description = "Skip crypto self-tests: cryptomgr.notests (faster boot).";
    };
    disableAudit = mkBoolOpt {
      default = true;
      description = "Disable audit subsystem: audit=0 (lower syscall overhead).";
    };
    noreplaceSmp = mkBoolOpt {
      default = true;
      description = "Do not replace SMP alternatives at runtime: noreplace-smp.";
    };
    idleNoMwait = mkBoolOpt {
      default = true;
      description = "Avoid MWAIT C-states: idle=nomwait (lower latency).";
    };
    disableUsbAutosuspend = mkBoolOpt {
      default = true;
      description = "Disable USB autosuspend: usbcore.autosuspend=-1.";
    };
    disableSplitLockDetect = mkBoolOpt {
      default = true;
      description = "Disable split lock detection: split_lock_detect=off.";
    };

    # Fancy zswap toggle and tuning
    zswap = {
      enable = mkEnableOption "Enable zswap compressed swap cache in RAM.";
      compressor = mkStrOpt {
        default = "zstd";
        description = "zswap compressor (e.g., zstd, lz4, lzo).";
        example = "zstd";
      };
      maxPoolPercent = mkIntOpt {
        default = 25;
        description = "Maximum percentage of RAM used by zswap pool.";
        example = 25;
      };
      zpool = mkStrOpt {
        default = "zsmalloc";
        description = "zswap zpool implementation (e.g., zsmalloc, zbud).";
        example = "zsmalloc";
      };
    };

    # Transparent Huge Pages policy
    thpMode = mkOpt (lib.types.nullOr (lib.types.enum ["always" "madvise" "never"])) null {
      description = "Transparent Huge Pages policy (kernel param transparent_hugepage). Null leaves kernel default.";
      example = "madvise";
      defaultText = "kernel default";
    };

    # CPU set for game pinning (used by modules/user/games game-run wrapper)
    gamingCpuSet = mkStrOpt {
      default = "";
      description = "Comma-separated CPU list for pinning game processes (e.g., 14,15,30,31). Empty disables default pinning.";
      example = "14,15,30,31";
    };

    # Enable CONFIG_SCHED_DEADLINE in the kernel (requires rebuild).
    # Helpful for desktop/workloads that benefit from SCHED_DEADLINE and
    # 6.8+ deadline-server improvements.
    schedDeadline = {
      enable = mkBoolOpt {
        default = true;
        description = "Ensure CONFIG_SCHED_DEADLINE=y (enables SCHED_DEADLINE class in kernel).";
      };
    };

    # PREEMPT_RT: enable realtime preemption in the kernel. Requires kernel >= 6.12
    # or using an RT-enabled kernel package. This may reduce throughput; use for
    # low-latency desktop/audio workloads.
    preemptRt = {
      enable = mkBoolOpt {
        default = false;
        description = "Enable PREEMPT_RT (CONFIG_PREEMPT_RT). Requires kernel >= 6.12 or RT kernel.";
      };
      mode = mkEnumOpt ["auto" "in-tree" "rt"] {
        default = "auto";
        description = "How to provide PREEMPT_RT: 'in-tree' toggles CONFIG_PREEMPT_RT in current kernel; 'rt' switches to linuxPackages_rt; 'auto' tries in-tree on >=6.12, else uses RT kernel.";
        example = "auto";
      };
    };
  };
}
