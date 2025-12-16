{
  lib,
  config,
  pkgs,
  ...
}:
lib.mkIf (config.features.web.enable && config.features.web.tools.enable) {
  # Tools moved to system-wide CLI package set (modules/cli/pkgs.nix) to keep
  # them available outside Home Manager.
  home.packages = [pkgs.neonmodem]; # TUI for Lemmy/Kbin
}
