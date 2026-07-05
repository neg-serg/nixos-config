##
# Module: system/boot
# Purpose: Bootloader (EFI, GRUB), initrd modules.
# Key options: none (uses config.boot.* directly).
# Dependencies: pkgs (efibootmgr/efivar/os-prober/sbctl).
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
    loader = {
      efi.canTouchEfiVariables = true;
      grub = {
        enable = lib.mkDefault false;
        device = lib.mkDefault "nodev"; # EFI only
        efiSupport = lib.mkDefault true;
      };
      # Skip boot menu unless a key is pressed; speeds up loader phase
      timeout = lib.mkDefault 0;
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
        compressor = "zstd";
        compressorArgs = [
          "-19"
          "-T0"
        ];
      })
    ];
  };
}
