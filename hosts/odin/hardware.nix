{
  pkgs,
  lib,
  config,
  ...
}:
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

    kernelParams = [
      # Runtime firmware search path — NixOS has no /lib/firmware; needed for
      # MediaTek MT6639 BT firmware (mediatek/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin)
      "firmware_class.path=/run/booted-system/firmware"
      "acpi_osi=!" # Fix ACPI compatibility on ASUS boards
      "acpi_osi=Linux" # Report Linux-compatible ACPI interface
      # video=3840x2160@240 removed: simpledrm rejects custom modelines, causes "User-defined mode not supported"
      # Limine resolution = "3840x2160" covers the bootloader resolution instead
      "lru_gen=1" # Enable multi-gen LRU page reclaim
      "lru_gen.min_ttl_ms=1000" # Min TTL for multi-gen LRU
      "mem_sleep_default=deep" # Prefer deep sleep (S3) for suspend
      "8250.nr_uarts=0" # Skip legacy UART probing
      "pcie_aspm=off" # Disable ASPM entirely — prevents NVMe D3cold wake delays on AMD/X670E
      "amd_pstate=active" # AMD P-State active mode: fastest transitions, native Zen 5 support
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

      # VFIO: iGPU (Granite Ridge 1002:13c0) + its HDMI audio (1002:1640) go to
      # the dockur Windows VM (Genelec GLM). Removes the iGPU from host Vulkan
      # so games/lsfg-vk can never land on it (display stays on the RX 9070 XT).
      "vfio-pci.ids=1002:13c0,1002:1640"
    ];

    # Load ASUS EC sensor driver for detailed telemetry + OpenRGB access
    kernelModules = lib.mkAfter [
      "ec_sys"
      "asus_ec_sensors"
      "snd-hdspe" # RME HDSPe driver (replaces in-tree snd-hdspm)
      "hid-playstation" # PlayStation controllers (DS4, DualSense, Edge) — pre-loaded before lockKernelModules
      "hid-sony" # Sony PS3 pads (Sixaxis/DS3) + PS Move
      "hidp" # Bluetooth classic HID profile (BT mice/keyboards/gamepads)
      "uhid" # Userspace HID — HID over GATT via bluez (modern BT gamepads)
    ];
    # amneziawg disabled — incompatible with certain kernel versions (ipv6_stub removed)
    # Plain list (no mkForce): lets the mt7927 module append its out-of-tree
    # mt76 package to boot.extraModulePackages (mkForce would drop it).
    extraModulePackages = (
      let
        # Wired through the overlay (packages/overlays/media.nix); the host
        # kernel is passed here since a kernel module must match the boot kernel.
        snd-hdspe = pkgs.snd-hdspe.override {
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

    # Load heavy GPU driver early in initrd to reduce userspace module-load time.
    # snd-seq loads here too: security.lockKernelModules sets
    # kernel.modules_disabled=1 during the real boot, after which NO module can
    # be loaded (silent EPERM). The initrd runs before that lock, so ALSA MIDI
    # (aconnect, Vital/SuperDirt MIDI) must come up here.
    initrd = {
      kernelModules = [
        "vfio_pci" # bind iGPU (vfio-pci.ids) BEFORE amdgpu claims it
        "amdgpu"
        "snd-seq" # ALSA sequencer core — MIDI (loaded pre-lock)
        "snd-seq-midi" # ALSA sequencer raw MIDI clients
      ];
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
          # Bootloader wallpaper — real image copied from ~/pic/wl/wallhaven-xep2dz.jpg
          wallpapers = [ ../../files/boot-splash.jpg ];
          wallpaperStyle = "stretched";
          backdrop = "000000";
        };
      };
    };

    # Enable AutoFDO (requires building kernel with Clang)
    kernel.autofdo.enable = false;

    # tpm/tpm_crb/tpm_tis and snd-hdspm already blacklisted in modules/system/kernel/params.nix
    blacklistedKernelModules = [
      "8250"
      "serial8250"
      "thunderbolt" # No Thunderbolt hardware connected; probe times out (-110) at boot
    ]
    ++ lib.optionals (!(config.lib.neg.enabled "security.tpmSudo")) [
      # TPM transport core; needed by fTPM for TPM-backed sudo
      # (modules/security/tpm-sudo.nix).
      "tpm_tis_core"
    ];
    # No separate initrd blacklist option; TPM modules are excluded from initrd
    # via modules/system/boot.nix when security.tpm2.enable = false
  };

  # kexec preparation hooks
  systemd.services.prepare-kexec = {
    serviceConfig.ExecStartPre = [
      # Export non-root ZFS pools before kexec so the new kernel imports
      # them cleanly (without -f). Skip pools that still have mounted
      # datasets (common for gamez during gameplay).
      (pkgs.writeShellScript "kexec-prepare-zfs" ''
        for pool in gamez zero; do
          if zpool status "$pool" >/dev/null 2>&1; then
            mounted="$(zfs list -H -o mounted "$pool" 2>/dev/null | grep -c yes || true)"
            if [ "$mounted" -eq 0 ]; then
              zpool export "$pool" 2>/dev/null || true
            fi
          fi
        done
      '')
      # Unbind discrete GPU (Radeon RX 9070 XT, Navi 48) from amdgpu
      # before kexec to force clean re-initialisation in the new kernel.
      # Without this, amdgpu may fail to reset GPU firmware/VRAM state
      # on kexec, causing lockup during initrd module load.
      (pkgs.writeShellScript "kexec-prepare-gpu" ''
        for slot in 0000:03:00.0 0000:7c:00.0; do
          path="/sys/bus/pci/drivers/amdgpu/$slot"
          if [ -e "$path" ]; then
            echo "$slot" > /sys/bus/pci/drivers/amdgpu/unbind 2>/dev/null || true
          fi
        done
      '')
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

    # Genelec GLM USB adapter (Gnet Adapter): 0666 so the dockur Windows VM's
    # QEMU (user-namespaced container, root -> host nobody) can open the node
    # for usb-host passthrough. Default 0644 root:root blocks it with EPERM.
    SUBSYSTEM=="usb", ATTR{idVendor}=="1781", ATTR{idProduct}=="0e39", MODE="0666"
    # Bind usbhid to the GLM adapter so a /dev/hidraw node exists (genlc's
    # hidraw backend needs it; the adapter does not auto-bind to usbhid).
    # NB: no DEVTYPE key — udevadm verify rejects it as an invalid match key.
    # ATTRS{idVendor}/ATTRS{idProduct} match the usb_interface event via its
    # parent chain; the device event's bind attempt is a harmless no-op.
    ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="1781", ATTRS{idProduct}=="0e39", RUN+="/bin/sh -c 'echo %k > /sys/bus/usb/drivers/usbhid/bind'"

    # Speed up NVMe boot: skip blkid probing for ZFS member partitions.
    # ZFS has its own label system — udev's blkid scan is wasted time
    # (saves ~1-2s per ZFS disk on boot).
    SUBSYSTEM=="block", ENV{ID_PART_ENTRY_TYPE}=="6a898cc3-1dd2-11b2-99a6-080020736631", \
      ENV{ID_FS_TYPE}=="zfs_member", OPTIONS+="nowatch"

    # Disable writeback throttling on NVMe — conflicts with ZFS's own I/O scheduler.
    # WBT adds latency jitter that ZFS doesn't need (ZFS schedules I/O internally).
    ACTION=="add|change", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", KERNEL=="nvme*n*", ATTR{queue/wbt_lat_usec}="0"

    # vfio group nodes (iGPU 7c:00.0/7c:00.1 → /dev/vfio/30,31) must be
    # world-accessible for the userns'd dockur QEMU (root -> host nobody),
    # same rationale as the GLM USB 0666 rule above.
    KERNEL=="vfio", MODE="0666"
    SUBSYSTEM=="vfio", MODE="0666"
  '';
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "kexec-rebuild" ''
      set -eu
      # Atomically rebuild the system and kexec into the new generation.
      # Passes any extra arguments (e.g. --flake, --use-remote-sudo) through.
      if [ "$${EUID:-}" -ne 0 ] && [ "$${UID:-}" -ne 0 ]; then
        echo "kexec-rebuild: must be run as root" >&2
        exit 1
      fi
      echo "=== Rebuilding NixOS ==="
      nixos-rebuild switch "$@"
      echo "=== kexec'ing into new generation ==="
      systemctl kexec
    '')
  ];

  # Skip unnecessary boot-time services (~1s saved)
  systemd.timers."fwupd-refresh".enable = false; # fwupdmgr refresh timer — manual refresh still works
  systemd.services.systemd-networkd-persistent-storage.enable = false; # declarative .link files handle naming

  # MediaTek MT6639/MT7927 BT RAM code — not in linux-firmware yet (only
  # WiFi blobs are); needed by the backported btmtk driver (btmtk_fw_get_filename
  # requests mediatek/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin for dev_id 0x6639).
  # Blob extracted from ASUS driver DRV_WiFi_MTK_MT7925_MT7927_TP_W11_64_V5603998_20250709R
  # (mtkwlan.dat) via jetm/mediatek-mt7927-dkms extract_firmware.py; sha256
  # 669c5c99a0c59c85c1285d3d1b8b31915c2d31341a2244f4eddcbfd60ffbbc76.
  hardware.firmware = lib.mkAfter [
    # compressFirmware = false: the xz-compress wrapper (compressFirmwareXz)
    # renames single-file packages with a hash prefix, which trips Nix's
    # "output not allowed to refer" check; plain blob is found fine by the
    # firmware loader.
    (pkgs.runCommand "mt6639-bt-firmware" { compressFirmware = false; } ''
      mkdir -p $out/lib/firmware/mediatek/mt7927
      # Explicit dest name: the imported store path keeps a hash prefix in its
      # basename, but the driver requests the plain filename.
      cp ${../../files/firmware/mediatek/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin} \
        $out/lib/firmware/mediatek/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin
    '')
  ];

  # dockur Windows VM + vfio (iGPU 1002:13c0 passthrough): QEMU must pin the
  # guest RAM (~14GB with RAM_SIZE=16G) for DMA into the vfio container, but
  # systemd/pam memlock defaults (8MB–4GB) are far below that → dma_map fails
  # with ENOMEM. Raise the lock limit for the whole user session. Three layers
  # are needed because the VM is started from user-space (rootless podman):
  # 1) system manager default (applies to system services incl. user@.service),
  # 2) user manager default (user units: dsh web, terminals under systemd --user),
  # 3) pam loginLimits (fresh login sessions; does not retrofit live ones).
  # Live sessions that predate this config still carry the old 4GiB hard limit;
  # remedy without reboot: sudo prlimit --pid <pid> --memlock=unlimited:unlimited
  # (see docs/howto/windows-vm-dockur.ru.md, "Грабли: memlock").
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
