{
  lib,
  config,
  pkgs,
  ...
}:
{
  config = lib.mkIf (config.features.web.enable && config.features.web.tools.enable) {
    # Tools moved to system-wide CLI package set (modules/cli/pkgs.nix) to keep
    # them available outside the profile.

  };
}
