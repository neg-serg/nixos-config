{
  lib,
  config,
  pkgs,
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
  valveIndexModule = {
    lib,
    pkgs,
    config,
    ...
  }: let
    vrCfg = config.hardware.vr.valveIndex;
  in {
    options.hardware.vr.valveIndex.enable =
      lib.mkEnableOption "Enable the Valve Index VR stack (OpenXR/SteamVR helpers, udev rules).";

    config = lib.mkIf vrCfg.enable {
      assertions = [
        {
          assertion = config.hardware.graphics.enable or false;
          message = "Valve Index VR requires hardware.graphics.enable = true.";
        }
      ];

      hardware.steam-hardware.enable = lib.mkDefault true;

      # Provide udev rules for XR devices (generic XR rules)
      services.udev.packages = lib.mkAfter [pkgs.xr-hardware];

      environment = {
        systemPackages = lib.mkAfter (with pkgs; [
          opencomposite
          openvr
          openxr-loader
          steam
          steamcmd
          vulkan-tools
          vulkan-validation-layers
          wlx-overlay-s
        ]);

        # No default OpenXR runtime enforced; user/SteamVR may set it explicitly if desired.
        sessionVariables = {};
      };
      # No extra user services; SteamVR runtime is expected to be used directly.
    };
  };
  imports = lib.filter (p: p != null) importables ++ [valveIndexModule];
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
      # Trim SSDs weekly (non-destructive), better than mount-time discard for sustained perf
      fstrim.enable = lib.mkDefault true;
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
