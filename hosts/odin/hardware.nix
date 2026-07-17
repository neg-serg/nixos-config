{
  pkgs,
  lib,
  config,
  ...
}:
{
  # Hardware and performance tuning specific to host 'odin'
  hardware = {
    storage.autoMount.enable = true;
    graphics = {
      enable = true;
      enable32Bit = true; # required for Proton/32-bit games (GL/Vulkan i686)
    };

    # Enable CoreCtrl with polkit rule for wheel
    gpu.corectrl = {
      enable = true;
      group = "wheel";
    };
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
      # V-Cache CCD (96MB L3) cores for gaming isolation
      gamingCpuSet = "1-3,16-19";
      # Standard CCD (32MB L3) for kernel/IRQ housekeeping
      housekeepingCpuSet = "4-15,20-31";
    };
    # Do not enable PREEMPT_RT on this host
    performance.preemptRt.enable = false;
  };

  # Performance profile comes from the workstation role

  # Writeback tuning: reduce IO bursts during gameplay/builds
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

  # Reduce ZFS forceImport risk: don't always force import on boot
  boot.zfs.forceImportRoot = false;

  # Host-specific kernel parameters and boot tuning
  boot = {
    # Use LTS kernel (ZFS doesn't build with latest 7.x)
    kernelPackages = lib.mkDefault pkgs.linuxPackages;

    kernelParams = [
      "acpi_osi=!" # Fix ACPI compatibility on ASUS boards
      "acpi_osi=Linux" # Report Linux-compatible ACPI interface
      # video=3840x2160@240 removed: simpledrm rejects custom modelines, causes "User-defined mode not supported"
      # Limine resolution = "3840x2160" covers the bootloader resolution instead
      "lru_gen=1" # Enable multi-gen LRU page reclaim
      "lru_gen.min_ttl_ms=1000" # Min TTL for multi-gen LRU
      "mem_sleep_default=deep" # Prefer deep sleep (S3) for suspend
      "8250.nr_uarts=0" # Skip legacy UART probing
      "pcie_aspm=off" # Disable ASPM entirely — prevents NVMe D3cold wake delays on AMD/X670E
      "pcie_port_pm=off" # Disable PCIe port power management — keeps NVMe accessible during import
      "nvme_core.io_timeout=4294967295" # Max NVMe I/O timeout
      "amdgpu.ppfeaturemask=0xffffffff" # Enable all AMD GPU overdrive features
      "udev.children_max=64" # Parallelize udev device init
      "udev.event_timeout=10" # Kill stuck udev workers after 10s
      "rd.udev.event_timeout=10" # Same for initrd udev
      "usbcore.initial_descriptor_timeout=2000" # Cut USB descriptor timeout from 5s to 2s (phantom port 8 on ASUS AM5)

      # Boot speed: skip unnecessary hardware probing
      "pci=noaer" # Skip AER (Advanced Error Reporting) — prevents NVMe probe timeouts on AMD/X670E
      "noresume" # Skip hibernation image search (no hibernate on this host)

      # Systemd boot optimizations: explicit config reduces probing delays
      "systemd.gpt_auto=0" # Skip GPT partition auto-discovery (fstab+ZFS are explicit)
      "systemd.default_device_timeout_sec=30" # Reduce device job timeout from 90s default

      # ZFS NVMe I/O tuning: parallelize metadata reads, batch writes, cap ARC
      "zfs.zfs_vdev_async_read_max_active=8" # 2.7x default (3): parallel metadata reads for NVMe pool import
      "zfs.zfs_vdev_aggregation_limit_non_rotating=1048576" # 8x default (128K): 1MB I/O aggregation for NVMe
      "zfs.zfs_async_block_max_blocks=100000" # Cap async destroy to prevent OOM on post-crash pool import
      "zfs.zfs_vdev_async_read_min_active=2" # 2x default (1): minimum concurrent async reads
      "zfs.zfs_arc_max=17179869184" # Cap ARC at 16GB on 64GB system (default: ~32GB auto)
    ];

    # Load ASUS EC sensor driver for detailed telemetry + OpenRGB access
    kernelModules = lib.mkAfter [
      "ec_sys"
      "asus_ec_sensors"
      "snd-hdspe" # RME HDSPe driver (replaces in-tree snd-hdspm)
    ];
    # amneziawg disabled — incompatible with certain kernel versions (ipv6_stub removed)
    extraModulePackages = lib.mkForce (
      let
        snd-hdspe = pkgs.callPackage ../../packages/snd-hdspe {
          kernel = config.boot.kernelPackages.kernel;
        };
      in
      lib.optional (builtins.hasAttr "asus-ec-sensors" config.boot.kernelPackages)
        config.boot.kernelPackages."asus-ec-sensors"
      ++
        lib.optional (builtins.hasAttr pkgs.zfs.kernelModuleAttribute config.boot.kernelPackages)
          config.boot.kernelPackages.${pkgs.zfs.kernelModuleAttribute}
      ++ [ snd-hdspe ]
    );

    # Load heavy GPU driver early in initrd to reduce userspace module-load time
    initrd = {
      kernelModules = [ "amdgpu" ];
      # Enable systemd in initrd; keep logs quiet for faster boot now
      systemd.enable = true;
      verbose = false;
    };

    # Lower console log level during/after boot; messages stay in journalctl
    consoleLogLevel = 3;

    loader = {
      timeout = 1; # seconds (1s to press any key, then boots immediately)
      limine = {
        enable = true;
        resolution = "3840x2160";
        enableEditor = true;
        style = {
          interface = {
            branding = "NixOS";
            brandingColor = "00D9FF";
            # Match autoboot countdown colour to the branding accent
            helpColor = "00AAAA";
            helpColorBright = "55FF55";
          };
          wallpapers = [ ../../files/boot-splash.jpg ];
          wallpaperStyle = "stretched";
          backdrop = "000000";
        };
        extraConfig = ''
          # Show boot entries
          DEFAULT_ENTRY=1
        '';
      };
    };

    # Enable AutoFDO (requires building kernel with Clang)
    kernel.autofdo.enable = false;

    # tpm/tpm_crb/tpm_tis and snd-hdspm already blacklisted in modules/system/kernel/params.nix
    blacklistedKernelModules = [
      "tpm_tis_core"
      "8250"
      "serial8250"
      "thunderbolt" # No Thunderbolt hardware connected; probe times out (-110) at boot
    ];
    # No separate initrd blacklist option; TPM modules are excluded from initrd
    # via modules/system/boot.nix when security.tpm2.enable = false
  };

  # Avoid double compression for swap
  zramSwap.enable = false;

  # Swap disabled: /mnt/zero volume being dismantled, swap was inactive anyway
  system.swapfile.enable = false;

  # Disable TPM entirely on this host to remove tpmrm device wait
  security.tpm2.enable = false;

  # NIC link renames
  systemd = {
    # Rename NICs to stable names via systemd-networkd link files
    network.links = {
      "10-net0" = {
        matchConfig.MACAddress = "a0:ad:9f:7e:4b:4e";
        linkConfig.Name = "net0";
      };
      "10-net1" = {
        matchConfig.MACAddress = "a0:ad:9f:7e:4b:4f";
        linkConfig.Name = "net1";
      };
    };
    # Disable systemd-boot-random-seed: saves ~1.024s blocking sysinit.target
    # Modern AMD CRNG initializes fast from RDRAND + jitter entropy w/o a saved seed
    services.systemd-boot-random-seed.enable = false;
  };

  # Host-specific hardware tools
  # Bakecore udev rules for Dygma keyboards
  services.udev.extraRules = ''
    # Dygma Raise
    SUBSYSTEM=="usb", ATTR{idVendor}=="35ef", ATTR{idProduct}=="0105", MODE="0666"
    # Dygma Defy
    SUBSYSTEM=="usb", ATTR{idVendor}=="35ef", ATTR{idProduct}=="0108", MODE="0666"

    # Speed up NVMe boot: skip blkid probing for ZFS member partitions.
    # ZFS has its own label system — udev's blkid scan is wasted time
    # (saves ~1-2s per ZFS disk on boot).
    SUBSYSTEM=="block", ENV{ID_PART_ENTRY_TYPE}=="6a898cc3-1dd2-11b2-99a6-080020736631", \
      ENV{ID_FS_TYPE}=="zfs_member", OPTIONS+="nowatch"

    # Disable writeback throttling on NVMe — conflicts with ZFS's own I/O scheduler.
    # WBT adds latency jitter that ZFS doesn't need (ZFS schedules I/O internally).
    ACTION=="add|change", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", KERNEL=="nvme*n*", ATTR{queue/wbt_lat_usec}="0"
  '';
  environment.systemPackages = [
  ];

  # Skip unnecessary boot-time services (~1s saved)
  systemd.timers."fwupd-refresh".enable = false; # fwupdmgr refresh timer — manual refresh still works
  systemd.services.systemd-networkd-persistent-storage.enable = false; # declarative .link files handle naming
}
