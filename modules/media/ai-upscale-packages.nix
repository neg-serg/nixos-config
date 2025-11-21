##
# Module: media/ai-upscale-packages
# Purpose: Provide AI upscaling dependencies system-wide when the feature is enabled.
{lib, config, pkgs, ...}: let
  cfg = config.features.media.aiUpscale or {};
  enabled = (config.features.gui.enable or false) && (cfg.enable or false);
  haveRealesrgan = pkgs ? realesrgan-ncnn-vulkan;
  haveFfmpeg = pkgs ? ffmpeg-full;
in {
  config = lib.mkIf enabled (lib.mkMerge [
    (lib.mkIf (haveRealesrgan && haveFfmpeg) {
      environment.systemPackages = lib.mkAfter [
        pkgs.realesrgan-ncnn-vulkan # GPU-accelerated ESRGAN upscaler (ncnn)
        pkgs.ffmpeg-full # ffmpeg build with Vulkan/CUDA needed for upscale scripts
      ];
    })
    (lib.mkIf (!(haveRealesrgan && haveFfmpeg)) {
      warnings = [
        "AI upscale feature enabled but realesrgan-ncnn-vulkan and/or ffmpeg-full are unavailable for this platform."
      ];
    })
  ]);
}
