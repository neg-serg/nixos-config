{
  pkgs,
  lib,
  config,
  ...
}:
let
  # Literal data tables live next to the consumer in hardware/ (no default.nix,
  # so hosts/odin's importDir { includeDirs = true; } leaves the directory alone).
  kernelData = import ./hardware/kernel.nix { inherit lib config pkgs; };
  systemData = import ./hardware/system.nix { inherit pkgs config; };
in
{
  # Zen 5: disable idle=nomwait — MWAIT C-states are optimal for Ryzen 9000
  profiles.performance.idleNoMwait = lib.mkForce false;
  # Hardware and performance tuning specific to host 'odin'
  hardware.graphics = {
    enable = true;
    enable32Bit = true; # required for Proton/32-bit games (GL/Vulkan i686)
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
      thpMode = "madvise"; # Prefer THP on madvise only to reduce jitter
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
  # ROCm compute (amdkfd + clr/rocm-smi userspace); torch-rocm env via features.dev.ai.rocm
  features.hardware.amdgpu.rocm.enable = true;
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
    # Use LTS kernel (ZFS doesn't build with latest 7.x)
    kernelPackages = lib.mkDefault pkgs.linuxPackages;

    # Removed the amdgpu-hmm-userptr-vm-bo-null backport (patch file kept at
    # files/patches/amdgpu-hmm-userptr-parent-fix.patch): upstream commit
    # 52f650963d88 ("drm/amdgpu: fix check in amdgpu_hmm_invalidate_gfx") is
    # first released in 6.18.42, so it is already present in the nixos-unstable
    # kernel (6.18.x). Re-applying it there fails because patch sees a reversed
    # (already-applied) hunk and exits non-zero. Do NOT re-add for kernels >= 6.18.42.

    kernelParams = kernelData.kernelParams;

    kernelModules = lib.mkAfter kernelData.kernelModules;
    extraModulePackages = kernelData.extraModulePackages;

    initrd = {
      kernelModules = kernelData.initrdKernelModules;
      # Enable systemd in initrd; keep logs quiet for faster boot now
      systemd.enable = true;
      verbose = false;
    };

    # Lower console log level during/after boot; messages stay in journalctl
    consoleLogLevel = 2; # was 3 — level 2 also hides KERN_CRIT, which is the
    # level amdgpu uses for "Overdrive is enabled, please disable it before
    # reporting any bugs unrelated to overdrive" (the overdrive bit 0x4000 in
    # amdgpu.ppfeaturemask below prints it on every boot; the bit stays because
    # CoreCtrl needs it for UV/OC). "quiet" alone does not cover it.

    loader = {
      # 0 = boot the default entry immediately. The boot menu is then only
      # reachable from the firmware/boot entry selection, which is the trade
      # taken for the second: Limine's countdown was the whole loader phase
      # (1.41s of a 20.6s boot), and the machine boots the same entry either way.
      timeout = 0;
      limine = {
        enable = true;
        resolution = "3840x2160";
        enableEditor = true;
        style = systemData.limineStyle;
      };
    };

    # Enable AutoFDO (requires building kernel with Clang)
    kernel.autofdo.enable = false;

    blacklistedKernelModules = kernelData.blacklistedKernelModules;
    # No separate initrd blacklist option; TPM modules are excluded from initrd
    # via modules/system/boot.nix when security.tpm2.enable = false
  };

  # kexec preparation hooks
  systemd.services.prepare-kexec = {
    serviceConfig.ExecStartPre = [
      systemData.kexecPrepareZfs
      systemData.kexecPrepareGpu
    ];
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
  services.udev.extraRules = config.lib.neg.readFile "files/hardware/udev/odin-host.rules";
  environment.systemPackages = [ systemData.kexecRebuild ];

  # Skip unnecessary boot-time services (~1s saved)
  systemd.timers."fwupd-refresh".enable = false; # fwupdmgr refresh timer — manual refresh still works
  systemd.services.systemd-networkd-persistent-storage.enable = false; # declarative .link files handle naming

  # MT6639/MT7927 Bluetooth firmware blob — see hardware/system.nix
  hardware.firmware = lib.mkAfter [ systemData.firmwareBlob ];

  # dockur Windows VM + vfio (iGPU 1002:13c0 passthrough): QEMU must pin the
  # guest RAM (~5-6GB with RAM_SIZE=6G) for DMA into the vfio container, but
  # systemd/pam memlock defaults (8MB–4GB) are far below that → dma_map fails
  # with ENOMEM. Raise the lock limit for the whole user session. Three layers
  # are needed because the VM is started from user-space (rootless podman):
  # 1) system manager default (applies to system services incl. user@.service),
  # 2) user manager default (user units: dsh web, terminals under systemd --user),
  # 3) pam loginLimits (fresh login sessions; does not retrofit live ones).
  # Live sessions that predate this config still carry the old 4GiB hard limit;
  # remedy without reboot: sudo prlimit --pid <pid> --memlock=unlimited:unlimited
  # (see docs/howto/windows-vm-dockur.md, "Pitfall: memlock").
  systemd.settings.Manager.DefaultLimitMEMLOCK = "infinity";
  systemd.user.settings.Manager.DefaultLimitMEMLOCK = "infinity";
  security.pam.loginLimits = lib.mkAfter [
    {
      domain = "neg";
      type = "-"; # soft + hard
      item = "memlock";
      value = "infinity";
    }
  ];
}
