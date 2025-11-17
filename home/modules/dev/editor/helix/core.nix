{
  lib,
  pkgs,
  config,
  ...
}:
lib.mkIf (config.features.dev.enable or false) {
  programs.helix = {
    enable = true;
    package = pkgs.helix;
  };
}
