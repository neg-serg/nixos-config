{ lib, pkgs, mkBool, ... }:
with lib;
{
  options.features = {
    hardware = {
      bluetooth.enable = mkBool "enable Bluetooth support" false;

      liquidctl = {
        enable = lib.mkEnableOption "Enable liquidctl tooling and optional init service for AIO/cooler controllers.";
        initCommand = lib.mkOption {
          type = lib.types.str;
          default = "${lib.getExe pkgs.liquidctl} initialize all";
          description = "Command to run at boot to initialize the cooler (default: initialize all).";
          example = "${lib.getExe pkgs.liquidctl} initialize all --fan-speed 60 --pump-speed 70";
        };
        runInit = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to run the init command at boot.";
        };
      };

      usbAutomount.enable = lib.mkEnableOption ''
        Enable udev-driven USB storage auto-mount via systemd service (mounts under /mnt/<label>).
      '';
    };
    input = {
      kanata.enable = mkBool "enable Kanata keyboard remapper (requires uinput module)" false;
      warpd.enable = mkBool "enable warpd (modal keyboard-driven pointer control)" false;
    };
  };
}
