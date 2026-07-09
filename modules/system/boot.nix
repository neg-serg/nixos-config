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

  # Ensure bootctl random-seed refresh waits for /boot to be
  # actually mounted, not just automount listener registered.
  # Avoids "Failed to open parent directory /boot: No such device"
  # race when NVMe takes longer to init than the service start.
  systemd.services.systemd-boot-random-seed = {
    unitConfig.RequiresMountsFor = "/boot";
  };

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
        compressor = "zstd";
        compressorArgs = [
          "-19"
          "-T0"
        ];
      })
    ];
  };
}
