##
# Module: hardware/liquidctl
# Purpose: Optional support for AIO/cooler controllers via liquidctl.
# Key options: features.hardware.liquidctl.enable
# Notes: Disabled by default; set enable=true on hosts with supported AIO.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.features.hardware.liquidctl or { enable = false; };
in
{
  options.features.hardware.liquidctl = {
    enable = lib.mkEnableOption "Enable liquidctl tooling and optional init service for AIO/cooler controllers.";
    initCommand = lib.mkOption {
      type = lib.types.str;
      default = "${lib.getExe pkgs.liquidctl} initialize all"; # Cross-platform CLI and Python drivers for AIO liquid cool...
      description = "Command to run at boot to initialize the cooler (default: initialize all).";
      example = "${lib.getExe pkgs.liquidctl} initialize all --fan-speed 60 --pump-speed 70"; # Cross-platform CLI and Python drivers for AIO liquid cool...
    };
    runInit = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to run the init command at boot.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = lib.mkAfter [ pkgs.liquidctl ]; # cooler control CLI (AIO/fans/RGB)

    systemd.services.liquidctl-init = lib.mkIf cfg.runInit {
      description = "Initialize AIO/cooler via liquidctl";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = cfg.initCommand;
      };
    };
  };
}
