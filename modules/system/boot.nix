##
# Module: system/boot
# Purpose: Bootloader (EFI, lanzaboote), initrd modules.
# Key options: none (uses config.boot.* directly).
# Dependencies: pkgs (efibootmgr/efivar/os-prober/sbctl), lanzaboote.
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
    lanzaboote = {
      enable = lib.mkDefault true;
      pkiBundle = "/etc/secureboot";
    };
    loader = {
      efi.canTouchEfiVariables = true;
      # With lanzaboote enabled, default systemd-boot to disabled; hosts may override.
      systemd-boot = {
        enable = lib.mkDefault false;
        # Use the highest available UEFI console resolution (often Full HD on 1080p displays).
        # If you need exactly 1920x1080, set a numeric mode ("0".."5") that matches your firmware's 1080p mode.
        # You can try values 0–5 and pick the one that renders at 1920x1080.
        consoleMode = lib.mkDefault "max";
        # Keep only a few generations in the boot menu to reduce loader work
        configurationLimit = lib.mkDefault 3;
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
        kernelModules = [ ];
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
