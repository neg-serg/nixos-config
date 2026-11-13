{
  pkgs,
  lib,
  config,
  neg,
  ...
}:
let
  # Literal data tables live next to the consumer in hardware/ (no default.nix,
  # so hosts/trantor's importDir { includeDirs = true; } leaves the directory alone).
  kernelData = import ./hardware/kernel.nix {
    inherit
      lib
      config
      pkgs
      neg
      ;
  };
  systemData = import ./hardware/system.nix { inherit pkgs config; };
in
{
  # Zen 5: disable idle=nomwait — MWAIT C-states are optimal for Ryzen 9000
  profiles.performance.idleNoMwait = lib.mkForce false;
  # Hardware and performance tuning specific to host 'trantor'
  hardware.graphics = {
    enable = true;
    enable32Bit = lib.mkForce false; # 32-bit games are not used; see the steam override in modules/user/games/launchers.nix
  };

  # Enable AMD-oriented kernel structured config for this host and tune performance
  profiles = {
    performance = {
      enable = true;
      # Avoid double compression
      zswap.enable = lib.mkDefault false;
      # Optimize initrd compression (smaller image, slower rebuilds)
      optimizeInitrdCompression = true;
      quietBoot = true; # Reduce boot verbosity to speed kernel + userspace stage slightly
      # 2 MiB pages for the Nix evaluator's ~3 GiB bdwgc heap: measured on a toplevel
      # eval, minor faults drop 802k -> 50k (-93.8 %) and wall clock 8.50 -> 7.63 s
      # (-10.3 %) with instructions unchanged, so the win is kernel-side page handling
      # rather than fewer computations. `madvise` was the old value, chosen to reduce
      # jitter, and it left the heap on 4 KiB pages because bdwgc never asks for huge
      # ones. Cost: eval RSS +2.15 % and the host's AnonHugePages peak roughly doubles.
      # modules/system/kernel/thp-policy.nix writes the same policy at activation, so a
      # switch applies it without waiting for a reboot.
      thpMode = "always";
      # Dial back aggressive defaults for desktop security/stability
      disableMitigations = false;
      disableAudit = false;
      skipCryptoSelftests = false;
      lowLatencyScheduling = true; # threadirqs + preempt=full — reduces IRQ jitter for audio/gaming
      noreplaceSmp = false; # Allow SMP alternatives patching on Zen 5 dual-CCD (9950X3D)
      # ASUS AM5 + NVMe D3cold workaround: disable ASPM + PCIe port PM
      pciePerformance = false;
      # CPU affinity kernel params (irqaffinity, kthread_cpus) — disabled.
      # Use cgroup cpuset (game-run) instead for more flexible pinning.
      cpuAffinity = false;
      # V-Cache CCD (96MB L3) cores for gaming isolation
      gamingCpuSet = "1-3,16-19";
      # Standard CCD (32MB L3) for kernel/IRQ housekeeping
      housekeepingCpuSet = "4-15,20-31";
    };
    # Do not enable PREEMPT_RT on this host
    performance.preemptRt.enable = false;
  };

  # ZRAM: zstd compressor (Zen 5 has hw-accelerated zstd, better ratio than lzo-rle)
  # SCX BPF scheduler — V-Cache CCD aware, replaces isolcpus
  features.optimization.enable = true;
  # ROCm compute (amdkfd + clr/rocm-smi userspace); training tooling via
  # features.dev.ai.rocm (nightjob; torch is a pip venv, not a Nix package)
  features.hardware.amdgpu.rocm.enable = true;
  # SteamVR async reprojection: Steam's bwrap user namespace cannot grant
  # CAP_SYS_NICE to vrcompositor, so lift amdgpu's high-priority-context check
  # instead. The patch header documents the scheduling-privilege tradeoff.
  features.hardware.amdgpu.ignoreCtxPrivileges = true;
  zramSwap.algorithm = "zstd";
  profiles.performance.writeback.enable = true;
  # Safe memory extras: lower swappiness and raise max_map_count for heavy apps/games
  profiles.performance.memExtras = {
    enable = true;
    # Align with gaming sysctl in modules/games to avoid conflicts
    swappiness = {
      enable = true;
      value = 10;
    };
    maxMapCount = {
      enable = true;
      value = 16777216;
    };
  };

  # forceImportRoot needed for kexec: ZFS pools aren't cleanly exported
  # during systemctl kexec (no orderly pool export on kexec reboot).
  # Without -f the new kernel's initrd would fail to import tank.
  boot.zfs.forceImportRoot = true;

  # Host-specific kernel parameters and boot tuning
  boot = {
    # Note: this is a fallback only — modules/system/kernel/localmodconfig.nix
    # overrides boot.kernelPackages (mkOverride 40) with the minimized kernel
    # built from the stable 7.3.1 sources.
    # The "ZFS does not build with latest 7.x" caveat is gone: nixpkgs ships
    # zfs_2_4 = 2.4.4, which upstream declares compatible with 6.18 through 7.2
    # (localmodconfig.nix lifts that ceiling for 7.3).
    kernelPackages = lib.mkDefault pkgs.linuxPackages;

    # The amdgpu-hmm-userptr backport is gone for good, not parked: upstream
    # commit 52f650963d88 ("drm/amdgpu: fix check in amdgpu_hmm_invalidate_gfx")
    # is first released in 6.18.42 and is present in every later kernel,
    # including 7.3.1, so re-applying it makes patch see a reversed hunk and die.

    kernelParams = kernelData.kernelParams;

    kernelModules = lib.mkAfter kernelData.kernelModules;
    extraModulePackages = kernelData.extraModulePackages;

    # The Radeon 610M iGPU (and its HDMI/DP audio) belongs to vfio-pci, not to
    # amdgpu: a guest VM drives the iGPU's USB4 Type-C DisplayPort-alt outputs
    # while the host keeps exactly one DRM device (the RX 9070 XT on DP-2).
    # The softdep loads vfio-pci before amdgpu, so the ids below win the probe
    # race; /etc/modprobe.d lands in the initrd, where amdgpu is loaded from.
    # Do not unbind amdgpu at runtime instead: its teardown hangs in D-state.
    extraModprobeConfig = ''
      options vfio-pci ids=1002:13c0,1002:1640
      softdep amdgpu pre: vfio-pci
    '';

    initrd = {
      kernelModules = kernelData.initrdKernelModules;
      # No `systemd.enable` / `verbose` here: the 2026-10 nixpkgs removed both
      # options together with the scripted stage 1, so systemd in initrd is the
      # only implementation left and the old quiet-boot switch no longer exists.
    };

    # Lower console log level during/after boot; messages stay in journalctl
    consoleLogLevel = 2; # was 3 — level 2 also hides KERN_CRIT, which is the
    # level amdgpu uses for "Overdrive is enabled, please disable it before
    # reporting any bugs unrelated to overdrive" (the overdrive bit 0x4000 in
    # amdgpu.ppfeaturemask below prints it on every boot; the bit stays because
    # CoreCtrl needs it for UV/OC). "quiet" alone does not cover it.

    loader = {
      # 0 = systemd-boot skips its own menu and boots the default entry. The
      # visible menu is NERV (first firmware entry): its countdown is the part
      # of the loader phase we pay for, and after the handoff systemd-boot
      # boots the same entry it would have picked anyway.
      timeout = 0;
      nerv = {
        enable = true;
        # The module's own NVRAM step aborts the whole bootloader install on
        # this host: /boot is a systemd automount, so `findmnt --target /boot`
        # prints the autofs row and the real device, and feeding that two-line
        # value to lsblk fails under the installer's `set -e`. The same checks
        # live in systemData.nervEfiEntry, tolerant of the two-line output.
        efiEntry.enable = false;
        settings = {
          timeout = 8; # seconds on the NERV countdown before autoboot
          bls-limit = 5; # generations shown in the menu (systemd-boot keeps 25)
        };
      };
    };

    # Enable AutoFDO (requires building kernel with Clang)
    kernel.autofdo.enable = false;
  };

  # NERV firmware entry — our own tolerant replacement for the module's
  # efiEntry step (see the boot.loader.nerv comment above).
  system.activationScripts.nervEfiEntry = lib.stringAfter [ "etc" ] (
    lib.getExe systemData.nervEfiEntry
  );

  # kexec preparation hooks
  systemd.services.prepare-kexec = {
    serviceConfig.ExecStartPre = [
      systemData.kexecPrepareZfs
      systemData.kexecPrepareGpu
    ];
  };

  # mt7925e: pin the chip out of runtime PM ("doze") and deep sleep — waking
  # from them is the path to "driver own failed" and a card that drops off the
  # bus (see the helper in hardware/system.nix for the verified debugfs
  # contract). The device unit re-applies after a driver rebind, since re-probe
  # resets both knobs to their defaults; multi-user covers the boot path where
  # mt7925e is preloaded from hardware/kernel.nix. No RemainAfterExit: a oneshot
  # that stays active would not run again on that rebind.
  systemd.services.mt7925-disable-pm = {
    description = "Pin MediaTek MT7925 out of runtime PM and deep sleep";
    after = [ "sys-subsystem-net-devices-wlan0.device" ];
    wantedBy = [
      "multi-user.target"
      "sys-subsystem-net-devices-wlan0.device"
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe systemData.mt7925PmOff;
    };
  };

  # Avoid double compression for swap
  zramSwap.enable = false;

  # Swap on Samsung 9100 PRO (507G). by-uuid: nvmeN device names reordered
  # between boots (was /dev/nvme0n1p2, now /dev/nvme1n1p2 after reboot).
  swapDevices = [ { device = "/dev/disk/by-uuid/452a938c-0183-4aac-8bfd-ef67ee2a2d59"; } ];

  # TPM is enabled via modules/security/tpm-sudo.nix when
  # features.security.tpmSudo.enable = true. Historically hard-disabled here
  # to remove the tpmrm device wait at boot — so leave it off unless TPM-backed
  # sudo is on, and enable fTPM in UEFI/BIOS first.

  # NIC link renames
  systemd = {
    network.links = systemData.networkLinks;
    # Disable systemd-boot-random-seed: saves ~1.024s blocking sysinit.target
    # Modern AMD CRNG initializes fast from RDRAND + jitter entropy w/o a saved seed
    services.systemd-boot-random-seed.enable = false;
  };

  # Host-specific hardware tools
  # Bakecore udev rules for Dygma keyboards
  # VFIO group nodes are created root-only, so every VM start needs sudo even
  # when the caller owns the setup. Handing them to the kvm group keeps the
  # device out of unprivileged reach while letting the desktop user run QEMU.
  services.udev.extraRules = ''
    ${config.lib.neg.readFile "files/hardware/udev/trantor-host.rules"}
    SUBSYSTEM=="vfio", GROUP="kvm", MODE="0660"
  '';
  environment.systemPackages = [ systemData.kexecRebuild ];

  # Skip unnecessary boot-time services (~1s saved)
  systemd.timers."fwupd-refresh".enable = false; # fwupdmgr refresh timer — manual refresh still works
  systemd.services.systemd-networkd-persistent-storage.enable = false; # declarative .link files handle naming

  # MT6639/MT7927 Bluetooth blob — see hardware/system.nix. Full linux-firmware
  # carries Intel/Qualcomm/NVIDIA/Mellanox blobs this host has no hardware for;
  # keep the AMD GPU, MediaTek MT7927 Wi-Fi/Bluetooth, Realtek RTL8126 and
  # regulatory files, plus alsa/sof for the audio DSPs.
  hardware.enableRedistributableFirmware = lib.mkForce false;
  hardware.cpu.amd.updateMicrocode = true;
  hardware.wirelessRegulatoryDatabase = true;
  hardware.firmware = lib.mkAfter [
    systemData.firmwareBlob
    pkgs.linux-firmware-minimal
    pkgs.alsa-firmware
    pkgs.sof-firmware
  ];

  # Raise the memlock limit for the whole user session. Three layers, because
  # workloads start from user space: 1) system manager default (applies to system
  # services incl. user@.service), 2) user manager default (user units), 3) pam
  # loginLimits (fresh login sessions; does not retrofit live ones).
  # Introduced for the dockur passthrough VM (2026-11), which is gone; the limits
  # stay as they are — tightening them is a separate tuning decision.
  # Live sessions that predate a change still carry the old 4GiB hard limit;
  # remedy without reboot: sudo prlimit --pid <pid> --memlock=unlimited:unlimited
  systemd.settings.Manager.DefaultLimitMEMLOCK = "infinity";
  systemd.user.settings.Manager.DefaultLimitMEMLOCK = "infinity";

  # VFIO group nodes are created root-only, so every VM start needs sudo even
  # when the caller owns the whole setup. Handing them to the kvm group keeps
  # the device out of unprivileged reach while letting the desktop user run
  # QEMU directly. The oneshot re-triggers udev for the vfio subsystem, so the
  # rule also lands in the running boot, not only after the next reboot.
  systemd.services.vfio-node-perms = {
    description = "Apply vfio device permissions to the existing group nodes";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${config.systemd.package}/bin/udevadm trigger --subsystem-match=vfio";
    };
  };
  security.pam.loginLimits = lib.mkAfter [
    {
      domain = "neg";
      type = "-"; # soft + hard
      item = "memlock";
      value = "infinity";
    }
  ];
}
