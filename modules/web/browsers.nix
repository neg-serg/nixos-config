{
  lib,
  config,
  pkgs,
  ...
}:
let
  webEnabled = (config.features.web.enable or false) || (config.features.web.yandex.enable or false);
in
{
  config = lib.mkIf webEnabled {
    environment.systemPackages = [
      pkgs.passff-host # native messaging host for PassFF Firefox extension
    ];
  };
}
