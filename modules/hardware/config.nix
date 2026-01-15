# Hardware configuration (options and config)
# Separated from default.nix to avoid double-import in flat module structure
{
  lib,
  config,
  ...
}:
let
  cfg = config.hardware.storage.autoMount;
  valveIndexModule =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      vrCfg = config.hardware.vr.valveIndex;
    in
    {
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
        services.udev.packages = lib.mkAfter [ pkgs.xr-hardware ]; # Hardware description for XR devices

        environment = {
          systemPackages = lib.mkAfter [
            pkgs.opencomposite # bridge OpenXR to OpenVR applications
            pkgs.openvr # OpenVR API library and headers
            pkgs.openxr-loader # OpenXR loader library
            pkgs.steam # Steam gaming platform
            pkgs.steamcmd # Steam command-line client
            pkgs.vulkan-tools # Vulkan diagnostic and testing tools
            pkgs.vulkan-validation-layers # Vulkan validation layers for development
            pkgs.wlx-overlay-s # Wayland overlay for OpenXR/OpenVR
          ];

          # No default OpenXR runtime enforced; user/SteamVR may set it explicitly if desired.
          sessionVariables = { };
        };
        # No extra user services; SteamVR runtime is expected to be used directly.
      };
    };
in
{
  imports = [ valveIndexModule ];

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
        enableAllFirmware = true; # Enable all the firmware
        usb-modeswitch.enable = true; # mode switching tool for controlling 'multi-mode' USB devices.
        enableRedistributableFirmware = true;
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
