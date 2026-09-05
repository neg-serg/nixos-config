#!/usr/bin/env bash
# ai-upscale-video — AI video upscaler on odin (AMD RX 9070 XT).
#
# Pipeline: VapourSynth (BestSource) -> vsncnn (ncnn Vulkan, ONNX models)
#           -> ffmpeg encode. Single pass, no intermediate PNGs.
#
# Models (assets live in /zero/ai/ per repo convention):
#   realesrgan-x4plus  — general-purpose 4x (23 RRDB), best quality.
#                        ~2.3 fps at 320x240, ~0.7 fps at 640x360 (GPU free).
#   animevideo-xsx2    — fast anime-tuned 2x, ~50 fps at 320x240.
#
# Usage:
#   ai-upscale-video FILE... [options]
#   Options:
#     --anime          use the fast anime 2x model (RealESRGANv2-animevideo-xsx2)
#     --crf N          x264/x265 quality (default 16)
#     --preset P       x264/x265 preset (default medium)
#     --vcodec C       libx264 (default) or libx265
#     -o OUT           output path (single input only)
#   Output defaults to <input>_x4_realesrgan.mp4 (x2 for --anime) next to the source.
#
# Note: x4plus is meant for SD/<=720p sources or paused-frame inspection;
# upscaling 1080p to 4320p runs at ~0.1 fps and eats VRAM. For anime at
# playback-like resolutions prefer --anime (2x).
set -euo pipefail

# VapourSynth plugin config is exported by the NixOS session env;
# fall back to the newest store copy for bare shells (cron/ssh/tests).
if [ -z "${VAPOURSYNTH_CONF_PATH:-}" ] || [ ! -f "${VAPOURSYNTH_CONF_PATH:-}" ]; then
  VAPOURSYNTH_CONF_PATH="$(ls -t /nix/store/*-vapoursynth.conf 2>/dev/null | head -n 1 || true)"
fi
if [ -n "$VAPOURSYNTH_CONF_PATH" ]; then export VAPOURSYNTH_CONF_PATH; fi

MODEL_X4="/zero/ai/imgproc/realesrgan-x4plus.onnx"
MODEL_XSX2="/zero/ai/imgproc/vsmlrt-v15.16/models/RealESRGANv2/RealESRGANv2-animevideo-xsx2.onnx"

usage() { sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 1; }

model="x4plus"
crf=16
preset="medium"
vcodec="libx264"
out_opt=""

while [ $# -gt 0 ]; do
  case "$1" in
    --anime) model="xsx2"; shift ;;
    --crf)   crf="$2"; shift 2 ;;
    --preset) preset="$2"; shift 2 ;;
    --vcodec) vcodec="$2"; shift 2 ;;
    -o|--out) out_opt="$2"; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "ai-upscale-video: unknown option: $1" >&2; usage ;;
    *) break ;;
  esac
done
[ $# -ge 1 ] || usage
[ -n "$out_opt" ] && [ $# -gt 1 ] && { echo "ai-upscale-video: -o works with a single input only" >&2; exit 2; }

if [ "$model" = "x4plus" ]; then
  ONNX="$MODEL_X4"; tag="4"
else
  ONNX="$MODEL_XSX2"; tag="2"
fi

for tool in ffmpeg ffprobe vspipe; do
  command -v "$tool" >/dev/null || { echo "ai-upscale-video: missing dependency: $tool" >&2; exit 3; }
done
[ -f "$ONNX" ] || { echo "ai-upscale-video: model not found: $ONNX" >&2; exit 3; }

upscale_one() {
  local in out stem dir vspid rc
  in="$(readlink -f "$1")"
  [ -f "$in" ] || { echo "ai-upscale-video: not a file: $in" >&2; return 1; }
  if [ -n "$out_opt" ]; then out="$(readlink -f "$out_opt")"; else
    stem="$(basename "$in" | sed 's/\.[^.]*$//')"
    dir="$(dirname "$in")"
    out="$dir/${stem}_x${tag}_realesrgan.mp4"
  fi
  [ "$in" = "$out" ] && { echo "ai-upscale-video: input == output, refusing" >&2; return 1; }

  work="$(mktemp -d /tmp/ai-upscale.XXXXXX)"
  trap 'rm -rf "$work"' EXIT RETURN
  fifo="$work/pipe.y4m"; vpy="$work/up.vpy"
  mkfifo "$fifo"
  cat > "$vpy" <<'PY'
import os, vapoursynth as vs
core = vs.core
src = core.bs.VideoSource(os.environ['AIUP_IN'])
rgb = core.resize.Bicubic(src, format=vs.RGBS, matrix_in_s='709')
out = core.ncnn.Model(clips=[rgb], network_path=os.environ['AIUP_ONNX'])
clip = core.resize.Bicubic(out, format=vs.YUV420P8, matrix_s='709')
clip.set_output()
PY

  echo "[ai-upscale] $in -> $out ($model, scale x$tag, $vcodec crf $crf)"
  AIUP_IN="$in" AIUP_ONNX="$ONNX" vspipe -c y4m -p "$vpy" "$fifo" 2> "$work/vspipe.log" &
  vspid=$!
  sleep 1
  kill -0 "$vspid" 2>/dev/null || { cat "$work/vspipe.log" >&2 || true; wait "$vspid" || true; return 1; }

  ffmpeg -hide_banner -loglevel error -y     -f yuv4mpegpipe -i "$fifo" -i "$in"     -map 0:v:0 -map 1:a?     -c:v "$vcodec" -preset "$preset" -crf "$crf" -pix_fmt yuv420p     -colorspace bt709 -color_primaries bt709 -color_trc bt709     -c:a copy -movflags +faststart -shortest "$out"
  rc=$?
  wait "$vspid" || true
  if [ $rc -eq 0 ]; then
    tail -1 "$work/vspipe.log" | sed 's/^/  /' >&2 || true
    echo "[ai-upscale] done: $out" >&2
  else
    echo "[ai-upscale] FAILED: $out" >&2
    return 1
  fi
}

fail=0
for f in "$@"; do upscale_one "$f" || fail=1; done
exit $fail
