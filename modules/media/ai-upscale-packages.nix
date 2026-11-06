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
  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") {
    inherit pkgs;
    nix = config.nix.package;
  };
in
{
  config = lib.mkIf enabled (
    lib.mkMerge [
      (lib.mkIf (haveRealesrgan && haveFfmpeg) {
        environment.systemPackages = lib.mkAfter [
          # Launchers only: the upscale CLI and the Vulkan/CUDA ffmpeg build
          # are used by hand (upscale-image, occasional encodes), not by every
          # session, and together they were 322 MiB of the closure.
          #
          # mpv's Alt+I upscale does not go through either of them: it runs
          # vsncnn in-process with the model under /zero (see
          # modules/user/nix-maid/scripts/realesrgan.vpy and vapoursynth-packages),
          # which stays installed.
          (onDemand {
            name = "realesrgan-ncnn-vulkan";
            attr = "realesrgan-ncnn-vulkan";
          })
          # `ffmpeg` on PATH stays the regular build; call `ffmpeg-full` when a
          # filter needs libplacebo/Vulkan or CUDA.
          (onDemand {
            name = "ffmpeg-full";
            attr = "ffmpeg-full";
            binary = "ffmpeg";
          })
          # NB: rembg intentionally NOT here — nixpkgs rembg builds onnxruntime from
          # source (libhwy) and gets OOM-killed on this host. Installed in a pip
          # venv instead (/zero/ai/music-ai/venv-rembg), see packages/local-bin/bin/rembg.
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
