{
  lib,
  config,
  pkgs,
  ...
}: let
  enabled = (config.features.gui.enable or false) && (config.features.media.aiUpscale.enable or false);
  packages = [
    pkgs.vapoursynth
    pkgs.python3Packages.vapoursynth
  ];
in {
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
