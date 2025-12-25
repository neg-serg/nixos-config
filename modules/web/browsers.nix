{
  lib,
  config,
  pkgs,
  ...
}: let
  webEnabled = config.features.web.enable or false;
in {
  config = lib.mkIf webEnabled {
    environment.systemPackages = lib.mkAfter [
      pkgs.passff-host # native messaging host for PassFF Firefox extension
    ];
  };
}
