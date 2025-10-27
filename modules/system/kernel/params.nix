##
# Module: system/kernel/params
# Purpose: Compose boot.kernelParams and related kernel package/module settings.
# Key options: cfg = config.profiles.performance.*, config.profiles.security.enable
# Dependencies: Uses pkgs; respects kexec_enabled.
{
  lib,
  pkgs,
  config,
  kexec_enabled,
  ...
}: let
  # Toggles from profiles/performance.nix
  perfEnabled = config.profiles.performance.enable or false;
  # Avoid self-referencing config.boot.kernelPackages when deciding RT mode.
  # Using pkgs.linuxPackages breaks the evaluation cycle with boot.kernelPackages overrides.
  kver = pkgs.linuxPackages.kernel.version or "";
  haveAtLeast = v: (kver != "") && lib.versionAtLeast kver v;
  prtEnable = config.profiles.performance.preemptRt.enable or false;
  prtMode = (config.profiles.performance.preemptRt.mode or "auto");
  useRtKernel = prtEnable && (prtMode == "rt" || (prtMode == "auto" && !haveAtLeast "6.12"));

  mitigations_settings = ["mitigations=off"]; # full mitigations disable
  silence = [
    "quiet"
    # Hide status in initrd completely for minimal output
    "rd.systemd.show_status=false"
    "rd.udev.log_priority=3"
    # Lower kernel and userspace verbosity on the console
    "loglevel=3"
    "udev.log_priority=3"
    "splash"
    "systemd.show_status=false"
    "vt.global_cursor_default=0"
  ];
  intel_hda_modules = [
    "snd_hda_codec"
    "snd_hda_codec_hdmi"
    "snd_hda_core"
    "snd_hda_intel"
  ];
  extra_security = ["page_alloc.shuffle=1"];
  idle_nomwait = ["idle=nomwait"]; # latency over power
  usb_noautosuspend = ["usbcore.autosuspend=-1"]; # avoid hiccups
  no_watchdog = [
    "nowatchdog"
    "kernel.nmi_watchdog=0"
  ];
  obscure_network_protocols = ["ax25" "netrom" "rose"];
  old_rare_insufficiently_audited_fs = [
    "adfs"
    "affs"
    "befs"
    "bfs"
    "cramfs"
    "efs"
    "erofs"
    "exofs"
    "freevxfs"
    "gfs2"
    "hfs"
    "hfsplus"
    "hpfs"
    "jffs2"
    "jfs"
    "ksmbd"
    "minix"
    "nilfs2"
    "omfs"
    "qnx4"
    "qnx6"
    "squashfs"
    "sysv"
    "ufs"
    "vivid"
  ];

  base_params = [
    # Keep classic interface names for consistency
    "net.ifnames=0"
    # Kernel and early userspace verbosity
    "loglevel=7"
    # Show systemd unit status during boot (stage-1 and stage-2)
    "rd.systemd.show_status=true"
    "systemd.show_status=true"
    # Make udev a bit more chatty (initrd + real root)
    "rd.udev.log_priority=info"
    "udev.log_priority=info"
  ];

  perf_params =
    lib.optionals config.profiles.performance.disableAudit ["audit=0"]
    ++ lib.optionals config.profiles.performance.skipCryptoSelftests ["cryptomgr.notests"]
    ++ lib.optionals config.profiles.performance.noreplaceSmp ["noreplace-smp"]
    ++ lib.optionals config.profiles.performance.pciePerformance ["pcie_aspm=performance"]
    ++ lib.optionals config.profiles.performance.lowLatencyScheduling ["preempt=full" "threadirqs"]
    ++ lib.optionals config.profiles.performance.fastRCU ["rcupdate.rcu_expedited=1"]
    ++ lib.optionals config.profiles.performance.trustTSC ["tsc=reliable"]
    ++ lib.optionals config.profiles.performance.disableSplitLockDetect ["split_lock_detect=off"]
    ++ lib.optionals config.profiles.performance.disableMitigations mitigations_settings
    ++ lib.optionals config.profiles.performance.quietBoot silence
    ++ lib.optionals config.profiles.performance.disableWatchdogs no_watchdog
    ++ lib.optionals config.profiles.performance.idleNoMwait idle_nomwait
    ++ lib.optionals config.profiles.performance.disableUsbAutosuspend usb_noautosuspend
    ++ lib.optionals ((config.profiles.performance.thpMode or null) != null) [
      "transparent_hugepage=${config.profiles.performance.thpMode}"
    ]
    ++ [
      "amd_pstate=active"
      "nvme_core.default_ps_max_latency_us=0"
    ]
    ++ lib.optionals (config.profiles.performance.zswap.enable or false) [
      "zswap.enabled=1"
      "zswap.compressor=${config.profiles.performance.zswap.compressor}"
      "zswap.max_pool_percent=${builtins.toString config.profiles.performance.zswap.maxPoolPercent}"
      "zswap.zpool=${config.profiles.performance.zswap.zpool}"
    ];
in {
  # Use mkMerge to contribute to boot.kernelParams in two phases:
  # 1) base_params go first (mkBefore) to guarantee ordering
  # 2) the rest of params are appended normally and can be overridden/extended by hosts
  config = lib.mkMerge [
    {
      boot = {
        # Keep core modules here; amdgpu is moved to initrd on AMD host to avoid userspace load delays
        kernelModules = ["kvm-amd" "tcp_bbr" "ntsync"];
        blacklistedKernelModules =
          ["sp5100_tco"]
          ++ obscure_network_protocols
          ++ intel_hda_modules
          ++ old_rare_insufficiently_audited_fs;

        kernelParams = lib.mkBefore base_params;

        # Use amneziawg from the selected kernelPackages when available
        extraModulePackages = let kp = config.boot.kernelPackages; in lib.optionals (kp ? amneziawg) [ kp.amneziawg ];
        # Default kernel console verbosity; hosts may override
        consoleLogLevel = lib.mkDefault 7;
        # Prefer mainstream kernel with Hydra substitutes to avoid local builds
        kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
      };
    }
    {
      # PREEMPT_RT + SCHED_DEADLINE kernel config toggles
      boot.kernelPatches = lib.mkMerge [
        (lib.mkIf (prtEnable && !useRtKernel && haveAtLeast "6.12") [
          {
            name = "enable-preempt-rt";
            patch = null;
            extraStructuredConfig = with lib.kernel; {
              PREEMPT_RT = yes;
            };
          }
        ])
        (lib.mkIf (perfEnabled && (config.profiles.performance.schedDeadline.enable or false)) [
          {
            name = "enable-sched-deadline";
            patch = null;
            extraStructuredConfig = with lib.kernel; {
              SCHED_DEADLINE = yes;
            };
          }
        ])
      ];

      # Optionally switch to RT kernel package when requested or on auto (< 6.12)
      boot.kernelPackages = lib.mkIf useRtKernel (lib.mkForce pkgs.linuxPackages_rt);

      boot.kernelParams =
        lib.optionals perfEnabled perf_params
        ++ extra_security
        ++ lib.optionals (config.profiles.security.enable or false) ["page_poison=1"];
      security.protectKernelImage = !kexec_enabled;
    }
  ];
}
