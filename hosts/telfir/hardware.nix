{
  pkgs,
  lib,
  config,
  ...
}:
{
  # Hardware and performance tuning specific to host 'telfir'
  hardware = {
    storage.autoMount.enable = true;
    vr.valveIndex.enable = false;
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
    kernel.amd.enable = false;
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
      lowLatencyScheduling = false; # With PREEMPT_RT enabled, drop extra low-latency cmdline toggles
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

  # Host-specific kernel parameters and boot tuning
  boot = {
    kernelParams = [
      "acpi_osi=!"                             # Fix ACPI compatibility on ASUS boards
      "acpi_osi=Linux"                         # Report Linux-compatible ACPI interface
      "video=3840x2160@240"                    # Set display resolution for early KMS
      "lru_gen=1"                              # Enable multi-gen LRU page reclaim
      "lru_gen.min_ttl_ms=1000"                # Min TTL for multi-gen LRU
      "mem_sleep_default=deep"                 # Prefer deep sleep (S3) for suspend
      "8250.nr_uarts=0"                        # Skip legacy UART probing
      "nvme_core.default_ps_max_latency_us=0"  # Disable NVMe APST (fixes 70s boot)
      "nvme_core.io_timeout=4294967295"        # Max NVMe I/O timeout
      "pcie_aspm=performance"                  # Disable PCIe power saving
      "usbcore.autosuspend=-1"                 # Disable USB autosuspend
      "amdgpu.ppfeaturemask=0xffffffff"        # Enable all AMD GPU overdrive features
      "udev.children_max=32"                   # Parallelize udev device init
      "udev.event_timeout=10"                  # Fix 60s USB port hang on ASUS AM5
    ];

    # Load ASUS EC sensor driver for detailed telemetry + OpenRGB access
    kernelModules = lib.mkAfter [
      "ec_sys"
      "asus_ec_sensors"
      "snd-hdspe" # RME HDSPe driver (replaces in-tree snd-hdspm)
    ];
    # amneziawg disabled — incompatible with 7.1.1-cachyos (ipv6_stub removed)
    extraModulePackages = lib.mkForce (
      let
        snd-hdspe = pkgs.callPackage ../../packages/snd-hdspe {
          kernel = config.boot.kernelPackages.kernel;
          lld = pkgs.llvmPackages_22.lld;
        };
      in
      lib.optional (builtins.hasAttr "asus-ec-sensors" config.boot.kernelPackages)
        config.boot.kernelPackages."asus-ec-sensors"
      ++ lib.optional (builtins.hasAttr "zfs" config.boot.kernelPackages)
        config.boot.kernelPackages.zfs
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

    # Disable lanzaboote — Secure Boot is off, PKI bundle not provisioned
    lanzaboote.enable = false;
    loader = {
      timeout = 2; # seconds
      # Use systemd-boot instead of lanzaboote
      systemd-boot = {
        enable = true;
        editor = true;
      };
    };

    # Enable AutoFDO (requires building kernel with Clang)
    kernel.autofdo.enable = false;
  };

  # Avoid double compression for swap
  zramSwap.enable = false;

  # Ensure the on-disk swapfile exists if missing (100G on root)
  system.swapfile = {
    enable = true;
    path = "/mnt/zero/swapfile";
    sizeGiB = 100;
  };

  # Disable TPM entirely on this host to remove tpmrm device wait
  security.tpm2.enable = false;
  boot.blacklistedKernelModules = [
    "tpm"
    "tpm_crb"
    "tpm_tis"
    "tpm_tis_core"
    "8250"
    "serial8250"
    "snd-hdspm" # Replaced by out-of-tree snd-hdspe
  ];
  # No separate initrd blacklist option; TPM modules are excluded from initrd
  # via modules/system/boot.nix when security.tpm2.enable = false

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
  };

  # Host-specific hardware tools
  services.udev.packages = [ pkgs.bazecor ];
  environment.systemPackages = [
    pkgs.bazecor # Dygma keyboard configurator
  ];
}
