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
