##
# Module: system/boot
# Purpose: Bootloader (Limine/EFI), initrd modules, kexec.
# Key options: none (uses config.boot.* directly).
# Dependencies: pkgs (efibootmgr/efivar/os-prober).
{
  lib,
  config,
  ...
}:
{
  imports = [
    ./boot/pkgs.nix # Nix package manager
    ./boot/autofdo.nix
  ];
  boot = {
    # Full kexec/kdump support — enables prepare-kexec.service for systemctl kexec
    kexec.enable = true;

    loader = {
      efi.canTouchEfiVariables = true;
      timeout = lib.mkDefault 0; # Skip boot menu unless key pressed; speeds up loader phase
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
        ];
      }
      (lib.mkIf (config.profiles.performance.optimizeInitrdCompression or false) {
        # Use function form to avoid nixpkgs initrd-compressor-meta bug
        # where pkgs.lz4 resolves to the dev output (no binary)
        compressor = pkgs: "${lib.getBin pkgs.lz4}/bin/lz4";
        compressorArgs = [
          "-l" # legacy format required by kernel's LZ4 decompressor
        ];
        # lz4 decompresses ~5x faster than zstd -19, trading ~30% larger initrd
        # for ~0.5-1s faster initrd load on NVMe (decompress > read speed)
      })
    ];
  };
}
