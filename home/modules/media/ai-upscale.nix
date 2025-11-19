{
  lib,
  pkgs,
  config,
  ...
}: let
  mkLocalBin = import ../../../packages/lib/local-bin.nix {inherit lib;};
in
  with lib; let
    cfg = config.features.media.aiUpscale or {};
  in
    lib.mkIf ((config.features.gui.enable or false) && (cfg.enable or false)) (
      let
        haveRE = pkgs ? realesrgan-ncnn-vulkan;
        haveFF = pkgs ? ffmpeg-full;
        upscaleScript = mkLocalBin "ai-upscale-video" ''          #!/usr/bin/env bash
                set -euo pipefail
                if [ $# -lt 1 ]; then
                  echo "Usage: ai-upscale-video <input> [--anime] [--scale 4] [--crf 16]" >&2
                  exit 1
                fi
                in="$1"; shift || true
                model="realesrgan-x4plus"
                scale=4
                crf=16
                while [ $# -gt 0 ]; do
                  case "$1" in
                    --anime) model="realesrgan-x4plus-anime"; shift ;;
                    --scale)
                      if [ $# -ge 2 ]; then scale="$2"; shift 2; else shift; fi ;;
                    --crf)
                      if [ $# -ge 2 ]; then crf="$2"; shift 2; else shift; fi ;;
                    *) echo "Unknown arg: $1" >&2; exit 2 ;;
                  esac
                done

                if ! command -v ffmpeg >/dev/null || ! command -v realesrgan-ncnn-vulkan >/dev/null; then
                  echo "Missing dependencies: ffmpeg and realesrgan-ncnn-vulkan must be in PATH" >&2
                  exit 3
                fi

                in_abs=$(readlink -f "$in")
                base_dir=$(dirname "$in_abs")
                base_name=$(basename "$in_abs")
                stem=$(printf '%s' "$base_name" | sed 's/\.[^.]*$//')
                out="$base_dir/$stem"_x"$scale"_realesrgan.mp4

                cache_root="$HOME/.cache/ai-upscale"
                mkdir -p "$cache_root"
                work=$(mktemp -d "$cache_root/work.XXXXXX")
                trap 'rm -rf "$work"' EXIT
                frames="$work/frames"; up="$work/up"
                mkdir -p "$frames" "$up"

                # Probe FPS from source
                fps=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "$in_abs" | awk -F/ '{ if ($2==""||$2==0) print $1; else printf("%.6f\n", $1/$2) }')
                [ -z "$fps" ] && fps=30

                echo "[ai-upscale] Extracting frames…" >&2
                ffmpeg -hide_banner -loglevel error -y -i "$in_abs" -map 0:v:0 -vsync 0 -pix_fmt rgb24 "$frames/%08d.png"

                echo "[ai-upscale] Upscaling with $model (x$scale)…" >&2
                realesrgan-ncnn-vulkan -i "$frames" -o "$up" -n "$model" -s "$scale" -f png >/dev/null

                echo "[ai-upscale] Encoding output…" >&2
                ffmpeg -hide_banner -loglevel error -y -framerate "$fps" -i "$up/%08d.png" -i "$in_abs" \
                  -map 0:v:0 -map 1:a? -map 1:s? -c:v libx264 -preset medium -crf "$crf" -pix_fmt yuv420p \
                  -c:a copy -c:s copy "$out"

                echo "[ai-upscale] Done: $out" >&2
        '';
      in
        lib.mkMerge [
          (lib.mkIf (haveRE && haveFF) {
            # Optional: quick launcher from mpv (Alt+U) to kick off offline upscale of current file
            programs.mpv.bindings = {
              "Alt+U" = lib.concatStringsSep "" [
                "run \"$HOME/.local/bin/ai-upscale-video\" \""
                "$"
                "{path}"
                "\""
              ];
            };
          })
          (lib.mkIf (haveRE && haveFF) upscaleScript)
        ]
    )
