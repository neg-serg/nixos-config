{
  lib,
  config,
  ...
}: let
  cfg = config.hardware.storage.autoMount;
  here = ./.;
  entries = builtins.readDir here;
  importables =
    lib.mapAttrsToList (
      name: type: let
        path = here + "/${name}";
      in
        if type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix"
        then path
        else if type == "directory" && builtins.pathExists (path + "/default.nix")
        then path
        else null
    )
    entries;
  imports = lib.filter (p: p != null) importables;
in {
  inherit imports;
  options.hardware.storage.autoMount.enable = lib.mkOption {
    type = lib.types.nullOr lib.types.bool;
    default = null;
    description = "Force enable/disable devmon (removable-media auto-mount). Null keeps module default (enabled).";
    example = true;
  };

  config = {
    services = {
      udisks2.enable = true;
      upower.enable = true;
      # Default to enabled, but allow per-host override via hardware.storage.autoMount.enable
      devmon.enable =
        if (cfg.enable or null) == null
        then lib.mkDefault true
        else cfg.enable;
      fwupd.enable = true;
    };

    hardware = {
      i2c.enable = true;
      bluetooth = {
        enable = true; # disable bluetooth
        powerOnBoot = false;
        settings = {General.Enable = "Source,Sink,Media,Socket";};
      };
      cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
      enableAllFirmware = true; # Enable all the firmware
      usb-modeswitch.enable = true; # mode switching tool for controlling 'multi-mode' USB devices.
      enableRedistributableFirmware = true;
    };

    # Packages moved to ./pkgs.nix

    powerManagement.cpuFreqGovernor = "performance";
  };
}
