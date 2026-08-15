{
  config,
  lib,
  pkgs,
  ...
}:
{
  environment.systemPackages = lib.optional (config.lib.neg.enabled "apps.throne") pkgs.throne;
}
