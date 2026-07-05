# Hardware configuration (options and config)
# Separated from default.nix to avoid double-import in flat module structure
{
  lib,
  config,
  ...
}:
let
  cfg = config.hardware.storage.autoMount;
in
{

  options.hardware.storage.autoMount.enable = lib.mkOption {
    type = lib.types.nullOr lib.types.bool;
    default = null;
    description = "Force enable/disable devmon (removable-media auto-mount). Null keeps module default (enabled).";
    example = true;
  };

  config = lib.mkMerge [
    {
      services = {
        udisks2.enable = true;
        upower.enable = true;
        # Default to enabled, but allow per-host override via hardware.storage.autoMount.enable
        devmon.enable = if (cfg.enable or null) == null then lib.mkDefault true else cfg.enable;
        fwupd.enable = true;
        # Trim SSDs weekly (non-destructive), better than mount-time discard for sustained perf
        fstrim.enable = lib.mkDefault true;
      };

      hardware = {
        i2c.enable = true;
        cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

        enableAllFirmware = false; # Disable installing ALL firmware to save space
        enableRedistributableFirmware = true; # Install standard distributable firmware
        firmwareCompression = "xz"; # Compress firmware (xz) to save space (requires kernel support)

        usb-modeswitch.enable = true; # mode switching tool for controlling 'multi-mode' USB devices.
      };

      # Packages moved to ./pkgs.nix

      powerManagement.cpuFreqGovernor = "performance";
    }
    (lib.mkIf (config.features.hardware.bluetooth.enable or false) {
      hardware.bluetooth = {
        enable = true; # disable bluetooth
        powerOnBoot = false;
        settings = {
          General.Enable = "Source,Sink,Media,Socket";
        };
      };
    })
  ];
}
