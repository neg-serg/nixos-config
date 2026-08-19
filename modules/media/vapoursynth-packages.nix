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
    pkgs.vapoursynth-bestsource # frame-accurate ffmpeg-based source (VS plugin)
    pkgs.vapoursynth-mvtools # motion estimation/compensation: denoise, deinterlace (VS plugin)
    pkgs.vsncnn # NCNN Vulkan runtime for VS: Real-ESRGAN/RIFE/Real-CUGAN/DPIR (GPL-3)
  ];
  pluginDirs = [
    "${pkgs.vsncnn}/lib"
    "${pkgs.vapoursynth-bestsource}/lib/vapoursynth"
    "${pkgs.vapoursynth-mvtools}/lib/vapoursynth"
  ];
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
    environment.variables.VAPOURSYNTH_PLUGINPATH = lib.concatStringsSep ":" pluginDirs;
  };
}
