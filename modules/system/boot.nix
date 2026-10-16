##
# Module: system/boot
# Purpose: Bootloader (systemd-boot + NERV/EFI), initrd modules, kexec.
# Key options: none (uses config.boot.* directly).
# Dependencies: pkgs (efibootmgr/efivar).
{
  lib,
  config,
  ...
}:
{
  # Sub-modules (pkgs, autofdo) are imported by boot/default.nix — the
  # readDir entry for this directory — so each file is imported exactly once.
  boot = {
    # Full kexec/kdump support — enables prepare-kexec.service for systemctl kexec
    # Protected by kernel.kexec_load_disabled=0 (kexec enabled, but gated by CAP_SYS_BOOT)
    kexec.enable = true;

    loader = {
      efi.canTouchEfiVariables = true;
      # systemd-boot owns the ESP side: it writes the BLS entries NERV lists,
      # does the actual booting after NERV's handoff, and keeps random-seed /
      # boot-counting state. NERV's own settings live in hosts/trantor.
      systemd-boot = {
        enable = true;
        configurationLimit = 25; # Keep at most 25 generations in boot menu
      };
      timeout = lib.mkDefault 0; # Skip the systemd-boot menu; NERV's countdown governs
    };
    # Boot-specific options only; no activation scripts touching /boot
    initrd = lib.mkMerge [
      {
        availableKernelModules = [
          "nvme"
          "sd_mod"
          "usb_storage"
          "usbhid"
          "xhci_hcd"
          "xhci_pci"
        ]
        # 7.2 defers AMD 800-series chipset controllers (Promontory 21, this
        # board's chipset) from xhci_pci to this driver, and lockKernelModules
        # forbids loading it after boot — so preload it in initrd. Gated on the
        # kernel version: a rollback of baseKernel to 6.18 (no such module)
        # must not break the initrd module closure.
        ++ lib.optionals (lib.versionAtLeast config.boot.kernelPackages.kernel.version "7.2") [
          "xhci_pci_prom21"
        ]
        # Load TPM modules in initrd only when TPM2 support is enabled
        ++ lib.optionals (config.security.tpm2.enable or false) [
          "tpm"
          "tpm_crb"
          "tpm_tis"
        ];
        kernelModules = [
          "usbhid"
          "xhci_hcd"
          "xhci_pci"
        ]
        ++ lib.optionals (lib.versionAtLeast config.boot.kernelPackages.kernel.version "7.2") [
          "xhci_pci_prom21" # AMD 800-series chipset USB (see above)
        ];
      }
      # Modules dropped from the kernel config (overlay.config H19). nixpkgs'
      # includeDefaultModules lists them for the initrd, and
      # allowMissingModules=false fails the initrd build when a listed module
      # is absent from the kernel, so the references are dropped explicitly.
      {
        availableKernelModules = {
          sata_nv = lib.mkForce false;
          sata_via = lib.mkForce false;
          sata_sis = lib.mkForce false;
          sata_uli = lib.mkForce false;
          pata_marvell = lib.mkForce false;
          uhci_hcd = lib.mkForce false;
          ehci_hcd = lib.mkForce false;
          ehci_pci = lib.mkForce false;
          ohci_hcd = lib.mkForce false;
          ohci_pci = lib.mkForce false;
          hid_lenovo = lib.mkForce false;
          hid_apple = lib.mkForce false;
          hid_roccat = lib.mkForce false;
          hid_microsoft = lib.mkForce false;
          hid_cherry = lib.mkForce false;
          hid_corsair = lib.mkForce false;
        };
      }
      (lib.mkIf (config.profiles.performance.optimizeInitrdCompression or false) {
        # Use function form to avoid nixpkgs initrd-compressor-meta bug
        # where pkgs.lz4 resolves to the dev output (no binary)
        compressor = pkgs: lib.getExe pkgs.lz4;
        compressorArgs = [
          "-l" # legacy format required by kernel's LZ4 decompressor
        ];
        # lz4 decompresses ~5x faster than zstd -19, trading ~30% larger initrd
        # for ~0.5-1s faster initrd load on NVMe (decompress > read speed)
      })
    ];
  };
  # kexec protection: disable kexec entirely. Nothing here uses it (boots go
  # through systemd-boot), and it removes the "load a kernel, then reboot into it"
  # primitive that bypasses the boot chain and measured boot.
  boot.kernel.sysctl."kernel.kexec_load_disabled" = lib.mkDefault 1;
}
