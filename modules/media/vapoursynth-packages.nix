{
  lib,
  config,
  pkgs,
  ...
}: let
  enabled = (config.features.gui.enable or false) && (config.features.media.aiUpscale.enable or false);
  packages = [
    pkgs.vapoursynth # video processing engine used by upscale scripts
    pkgs.python3Packages.vapoursynth # Python bindings for scripting filters
  ];
in {
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
