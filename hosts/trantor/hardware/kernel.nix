# Literal kernel/initrd data for host 'trantor', kept out of the module body so
# hardware.nix stays wiring. Data only: kernel parameters, module-name lists
# and the extra module packages. Comments travel with the data — they document
# the hardware quirks behind each entry.
{
  lib,
  config,
  pkgs,
}:
let
  # Wired through the overlay (packages/overlays/media.nix); the host
  # kernel is passed here since a kernel module must match the boot kernel.
  snd-hdspe = pkgs.snd-hdspe.override {
    kernel = config.boot.kernelPackages.kernel;
  };
in
{
  # Host-specific kernel parameters and boot tuning
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
    # ^ 0x4000 (overdrive bit) makes amdgpu log a KERN_CRIT notice on every boot.
    #   It cannot be suppressed selectively — hidden from the console via
    #   boot.consoleLogLevel = 2 and from the TTY viewers in modules/system/log-ttys.nix.
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
  kernelModules = [
    "ec_sys"
    "asus_ec_sensors"
    "snd-hdspe" # RME HDSPe driver (replaces in-tree snd-hdspm)
    "hid-playstation" # PlayStation controllers (DS4, DualSense, Edge) — pre-loaded before lockKernelModules
    "hid-sony" # Sony PS3 pads (Sixaxis/DS3) + PS Move
    "hidp" # Bluetooth classic HID profile (BT mice/keyboards/gamepads)
    "uhid" # Userspace HID — HID over GATT via bluez (modern BT gamepads)
    "rfcomm" # Bluetooth SPP (RFCOMM) — GalaxyBudsClient talks to the Buds over SPP; pre-loaded before lockKernelModules
    "uvcvideo" # USB webcams (UVC) — module pre-loaded before lockKernelModules; media core is modular so this cannot be built-in
    # snd-usb-audio is NOT pre-loaded: with features.security.lockKernelModules
    # off, modalias autoload brings it in for real gear (the Osmose), while a
    # preload makes systemd-modules-load wait for the onboard ASUS "USB Audio"
    # (0b05:1b7c) — 2026-10-01: the device showed up 2 m 18 s into the boot, so
    # the unit sat there for ~2.5 min. Autoload does the same job in background.
  ];

  # amneziawg disabled — incompatible with certain kernel versions (ipv6_stub removed)
  # Plain list (no mkForce): lets the mt7927 module append its out-of-tree
  # mt76 package to boot.extraModulePackages (mkForce would drop it).
  extraModulePackages =
    lib.optional (builtins.hasAttr "asus-ec-sensors" config.boot.kernelPackages)
      config.boot.kernelPackages."asus-ec-sensors"
    ++
      lib.optional (builtins.hasAttr pkgs.zfs.kernelModuleAttribute config.boot.kernelPackages)
        config.boot.kernelPackages.${pkgs.zfs.kernelModuleAttribute}
    ++ [ snd-hdspe ];

  # Load heavy GPU driver early in initrd to reduce userspace module-load time.
  # snd-seq loads here too: security.lockKernelModules sets
  # kernel.modules_disabled=1 during the real boot, after which NO module can
  # be loaded (silent EPERM). The initrd runs before that lock, so ALSA MIDI
  # (aconnect, Vital/SuperDirt MIDI) must come up here.
  initrdKernelModules = [
    "vfio_pci" # bind iGPU (vfio-pci.ids) BEFORE amdgpu claims it
    "amdgpu"
    "snd-seq" # ALSA sequencer core — MIDI (loaded pre-lock)
    "snd-seq-midi" # ALSA sequencer raw MIDI clients
  ];

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
}
