{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = (config.lib.neg.enabled "gui") && (config.lib.neg.enabled "media.aiUpscale");
  packages = [
    pkgs.vapoursynth # video processing engine used by upscale scripts
    pkgs.python3Packages.vapoursynth # Python bindings for scripting filters
  ];
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
