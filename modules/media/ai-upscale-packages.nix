##
# Module: media/ai-upscale-packages
# Purpose: Provide AI upscaling dependencies system-wide when the feature is enabled.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.features.media.aiUpscale or { };
  enabled = (config.lib.neg.enabled "gui") && (cfg.enable or false);
  haveRealesrgan = pkgs ? realesrgan-ncnn-vulkan;
  haveFfmpeg = pkgs ? ffmpeg-full;
in
{
  config = lib.mkIf enabled (
    lib.mkMerge [
      (lib.mkIf (haveRealesrgan && haveFfmpeg) {
        environment.systemPackages = lib.mkAfter [
          pkgs.realesrgan-ncnn-vulkan # GPU-accelerated ESRGAN upscaler (ncnn, Vulkan)
          pkgs.ffmpeg-full # ffmpeg build with Vulkan/CUDA needed for upscale scripts
          pkgs.upscayl # GUI batch upscaler (Vulkan), good for photo albums
          # NB: rembg intentionally NOT here — nixpkgs rembg builds onnxruntime from
          # source (libhwy) and gets OOM-killed on this host. Installed in a pip
          # venv instead (~/src/music-ai/venv-rembg), see packages/local-bin/bin/rembg.
        ];
      })
      (lib.mkIf (!(haveRealesrgan && haveFfmpeg)) {
        warnings = [
          "AI upscale feature enabled but realesrgan-ncnn-vulkan and/or ffmpeg-full are unavailable for this platform."
        ];
      })
    ]
  );
}
