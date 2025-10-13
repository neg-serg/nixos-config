{pkgs, ...}: {
  # Hardware and performance tuning specific to host 'telfir'
  hardware.storage.autoMount.enable = true;
  hardware.video.amd.useMesaGit = true;
  hardware.vr.valveIndex.enable = true;

  # Enable AMD-oriented kernel structured config for this host and tune performance
  profiles = {
    kernel.amd.enable = true;
    performance = {
      # Avoid double compression
      zswap.enable = false;
      # Optimize initrd compression (smaller image, slower rebuilds)
      optimizeInitrdCompression = true;
      # Reduce boot verbosity to speed kernel + userspace stage slightly
      quietBoot = true;
    };
  };

  # Performance profile comes from the workstation role

  # Host-specific kernel parameters and boot tuning
  boot = {
    kernelParams = [
      "acpi_osi=!"
      "acpi_osi=Linux"
      "video=3840x2160@240"
      # CPU isolation for gaming/low-latency (adjust to your topology)
      "nohz_full=14,15,30,31"
      "rcu_nocbs=14,15,30,31"
      "isolcpus=managed,domain,14-15,30-31"
      "irqaffinity=0-13,16-29"
      "lru_gen=1"
      "lru_gen.min_ttl_ms=1000"
      # Avoid probing dozens of legacy UARTs; speeds up device coldplug
      "8250.nr_uarts=1"
    ];

    # Load heavy GPU driver early in initrd to reduce userspace module-load time
    initrd = {
      kernelModules = ["amdgpu"];
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
  };

  # Avoid double compression for swap
  zramSwap.enable = false;

  # Disable TPM entirely on this host to remove tpmrm device wait
  security.tpm2.enable = false;
  boot.blacklistedKernelModules = [
    "tpm"
    "tpm_crb"
    "tpm_tis"
    "tpm_tis_core"
  ];
  # No separate initrd blacklist option; TPM modules are excluded from initrd
  # via modules/system/boot.nix when security.tpm2.enable = false

  # Keep services on housekeeping CPUs by default; IRQ balancing mask; NIC link renames
  systemd = {
    settings.Manager.CPUAffinity = ["0-13" "16-29"];
    services.irqbalance.environment.IRQBALANCE_BANNED_CPUS = "0xC000C000";
    # Rename NICs to stable names via systemd-networkd link files
    network.links = {
      "10-net0" = {
        matchConfig.MACAddress = "fc:34:97:b7:16:0e";
        linkConfig.Name = "net0";
      };
      "10-net1" = {
        matchConfig.MACAddress = "fc:34:97:b7:16:0f";
        linkConfig.Name = "net1";
      };
    };
  };

  # Host-specific hardware tools
  environment.systemPackages = [
    pkgs.bazecor # Dygma keyboard configurator
  ];
}
