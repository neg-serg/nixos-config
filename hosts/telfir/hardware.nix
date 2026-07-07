{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
let
  grubFont = derivation {
    name = "iosevka-36.pf2";
    system = pkgs.stdenv.hostPlatform.system;
    builder = "${pkgs.bash}/bin/bash";
    args = [
      "-c"
      "${pkgs.grub2}/bin/grub-mkfont -s 36 -o \"\$out\" \"\$FONT\""
    ];
    FONT = "${inputs.iosevka-neg.packages.x86_64-linux.nerd-font}/share/fonts/truetype/IosevkaNerdFont-Regular.ttf";
  };
in
{
  # Hardware and performance tuning specific to host 'telfir'
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
      lowLatencyScheduling = false; # With PREEMPT_RT enabled, drop extra low-latency cmdline toggles
      noreplaceSmp = false; # Allow SMP alternatives patching on Zen 5 dual-CCD (9950X3D)
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
    # Use LTS kernel (ZFS doesn't build with latest 7.x)
    kernelPackages = lib.mkForce pkgs.linuxPackages;

    kernelParams = [
      "acpi_osi=!" # Fix ACPI compatibility on ASUS boards
      "acpi_osi=Linux" # Report Linux-compatible ACPI interface
      # video=3840x2160@240 removed: simpledrm rejects custom modelines, causes "User-defined mode not supported"
      # GRUB gfxmodeEfi = "3840x2160" covers the bootloader resolution instead
      "lru_gen=1" # Enable multi-gen LRU page reclaim
      "lru_gen.min_ttl_ms=1000" # Min TTL for multi-gen LRU
      "mem_sleep_default=deep" # Prefer deep sleep (S3) for suspend
      "8250.nr_uarts=0" # Skip legacy UART probing
      # nvme_core.* / pcie_aspm / usbcore.autosuspend already covered by performance profile in params.nix
      "nvme_core.io_timeout=4294967295" # Max NVMe I/O timeout
      "amdgpu.ppfeaturemask=0xffffffff" # Enable all AMD GPU overdrive features
      "udev.children_max=32" # Parallelize udev device init
      "udev.event_timeout=10" # Kill stuck udev workers after 10s
      "rd.udev.event_timeout=10" # Same for initrd udev
      "usbcore.initial_descriptor_timeout=2000" # Cut USB descriptor timeout from 5s to 2s (phantom port 8 on ASUS AM5)
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
      timeout = 2; # seconds
      grub = {
        enable = true;
        device = "nodev"; # EFI only
        efiSupport = true;
        gfxmodeEfi = "3840x2160";
        gfxpayloadEfi = "keep";
        splashImage = ../../files/grub-splash.jpg;
        font = grubFont;
        backgroundColor = "#000000";
        extraConfig = ''
          set menu_color_normal=white/black
          set menu_color_highlight=black/white
        '';
      };
    };

    # Enable AutoFDO (requires building kernel with Clang)
    kernel.autofdo.enable = false;

    blacklistedKernelModules = [
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
  # Bakecore udev rules for Dygma keyboards
  services.udev.extraRules = ''
    # Dygma Raise
    SUBSYSTEM=="usb", ATTR{idVendor}=="35ef", ATTR{idProduct}=="0105", MODE="0666"
    # Dygma Defy
    SUBSYSTEM=="usb", ATTR{idVendor}=="35ef", ATTR{idProduct}=="0108", MODE="0666"
  '';
  environment.systemPackages = [
    pkgs.neg.bazecor # Dygma keyboard configurator (AppImage)
  ];
}
