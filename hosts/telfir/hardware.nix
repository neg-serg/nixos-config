{
  lib,
  pkgs,
  ...
}: {
  # Hardware and performance tuning specific to host 'telfir'
  hardware.storage.autoMount.enable = true;
  hardware.video.amd.useMesaGit = true;

  # Enable AMD-oriented kernel structured config for this host and tune performance
  profiles = {
    kernel.amd.enable = true;
    # Avoid double compression
    performance.zswap.enable = lib.mkForce false;
    # Optimize initrd compression (smaller image, slower rebuilds)
    performance.optimizeInitrdCompression = true;
  };

  # Performance profile comes from the workstation role

  # Host-specific kernel parameters
  boot.kernelParams = [
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
  ];

  # Load heavy GPU driver early in initrd to reduce userspace module-load time
  boot.initrd.kernelModules = ["amdgpu"];

  # Enable systemd in initrd and verbose logging for detailed early-boot profiling
  boot.initrd.systemd.enable = true;
  boot.initrd.verbose = true;

  # Make boot menu accessible during experiments: wait 1 second
  boot.loader.timeout = 1; # seconds
  # Allow editing kernel cmdline from the loader (useful for recovery)
  boot.loader.systemd-boot.editor = true;

  # Avoid double compression for swap
  zramSwap.enable = lib.mkForce false;

  # Keep services on housekeeping CPUs by default
  systemd.settings.Manager.CPUAffinity = ["0-13" "16-29"];
  # Ban isolated CPUs from IRQ balancing (Zen3 mask example)
  systemd.services.irqbalance.environment.IRQBALANCE_BANNED_CPUS = "0xC000C000";

  # Rename NICs to stable names specific to this host
  services.udev.extraRules = ''
    KERNEL=="eth*", ATTR{address}=="fc:34:97:b7:16:0e", NAME="net0"
    KERNEL=="eth*", ATTR{address}=="fc:34:97:b7:16:0f", NAME="net1"
  '';

  # Host-specific hardware tools
  environment.systemPackages = with pkgs; [
    bazecor # Dygma keyboard configurator
  ];
}
