{
  config,
  lib,
  pkgs,
  ...
}:
{
  environment.systemPackages = lib.optional (config.features.apps.throne.enable or false) pkgs.throne;
}
