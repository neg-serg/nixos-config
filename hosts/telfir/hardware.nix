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
    vr.valveIndex.enable = true;

    # Ensure Mesa stack for Steam/VR (64-bit only)
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
      # Reduce boot verbosity to speed kernel + userspace stage slightly
      quietBoot = true;
      # Prefer THP on madvise only to reduce jitter
      thpMode = "madvise";
      # Dial back aggressive defaults for desktop security/stability
      disableMitigations = false;
      disableAudit = false;
      skipCryptoSelftests = false;
      # With PREEMPT_RT enabled, drop extra low-latency cmdline toggles
      lowLatencyScheduling = false;
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
      "acpi_osi=!"
      "acpi_osi=Linux"
      "video=3840x2160@240"
      "lru_gen=1"
      "lru_gen.min_ttl_ms=1000"
      "mem_sleep_default=deep"
      # Avoid probing dozens of legacy UARTs; speeds up device coldplug
      "8250.nr_uarts=0"
    ];

    # Load ASUS EC sensor driver for detailed telemetry + OpenRGB access
    kernelModules = lib.mkAfter [
      "ec_sys"
      "asus_ec_sensors"
    ];
    extraModulePackages = lib.mkAfter (
      lib.optional (builtins.hasAttr "asus-ec-sensors" config.boot.kernelPackages)
        config.boot.kernelPackages."asus-ec-sensors"
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

    # Skip boot menu by default (can hold a key to show menu)
    loader = {
      timeout = 0; # seconds
      # Allow editing kernel cmdline from the loader (useful for recovery)
      systemd-boot.editor = true;
    };

    # Enable AutoFDO (requires building kernel with Clang)
    kernel.autofdo.enable = false;
  };

  # Avoid double compression for swap
  zramSwap.enable = false;

  # Ensure the on-disk swapfile exists if missing (80G on /zero)
  system.swapfile = {
    enable = true;
    path = "/zero/swapfile";
    sizeGiB = 80;
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
    pkgs.radeontop # AMD GPU utilization monitor
  ];
}
